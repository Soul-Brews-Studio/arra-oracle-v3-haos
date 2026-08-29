/**
 * Arra Studio add-on server — static Studio SPA + authenticated API proxy.
 *
 * Why this exists at all: the Studio frontend never sends an Authorization
 * header, and the backend add-on refuses to run without auth. So something
 * server-side must hold the key and inject it. That something must not hand
 * the corpus to whoever finds the LAN port, which is what the session gate
 * below is for:
 *
 *   - Requests arriving through HA ingress (verified by the Supervisor
 *     proxy's fixed address, not a spoofable header) see a launcher page
 *     carrying a single-use, short-lived token.
 *   - Opening the LAN origin with that token trades it for a session
 *     cookie; everything else on the LAN gets a refusal page.
 *   - With a session: static files serve the SPA, /api and /mcp proxy to
 *     the backend with the bearer injected. The key never leaves this
 *     process.
 *
 * Studio's API base is host-only by design (?host= query / localStorage),
 * so the injected bootstrap script points it at this server's own origin —
 * the documented mechanism, no vendor patch.
 */

const ORACLE_URL = (process.env.ORACLE_URL ?? '').replace(/\/+$/, '');
const ORACLE_API_KEY = process.env.ORACLE_API_KEY ?? '';
const DIST = process.env.STUDIO_DIST ?? '/app/frontend/dist';
const PORT = Number(process.env.PORT ?? 8100);
// The Supervisor ingress proxy always connects from this address.
const INGRESS_PEER = process.env.INGRESS_PEER ?? '172.30.32.2';

const TOKEN_TTL_MS = 5 * 60 * 1000;
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const MAX_PENDING_TOKENS = 64;

const pendingTokens = new Map<string, number>(); // token -> expiry
const sessions = new Map<string, number>(); // cookie value -> expiry

function randomToken(): string {
  return crypto.randomUUID().replaceAll('-', '') + crypto.randomUUID().replaceAll('-', '');
}

function sweep(map: Map<string, number>): void {
  const now = Date.now();
  for (const [k, exp] of map) if (exp < now) map.delete(k);
}

function mintToken(): string {
  sweep(pendingTokens);
  // A flood of launcher loads must not grow this map without bound.
  while (pendingTokens.size >= MAX_PENDING_TOKENS) {
    const oldest = pendingTokens.keys().next().value;
    if (oldest === undefined) break;
    pendingTokens.delete(oldest);
  }
  const token = randomToken();
  pendingTokens.set(token, Date.now() + TOKEN_TTL_MS);
  return token;
}

function hasSession(req: Request): boolean {
  sweep(sessions);
  const cookie = req.headers.get('cookie') ?? '';
  const value = cookie.match(/(?:^|;\s*)studio_session=([A-Za-z0-9]+)/)?.[1];
  return Boolean(value && sessions.has(value));
}

function launcherPage(token: string): Response {
  // The link target is computed in the browser: from inside the ingress
  // iframe, location.hostname is the Home Assistant host as the USER
  // reaches it, which is exactly the address the LAN origin lives on.
  const html = `<!doctype html>
<html><head><meta charset="utf-8"><title>Arra Studio</title>
<style>
  body{font-family:system-ui,sans-serif;background:#101418;color:#e6e6e6;
       display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
  main{text-align:center;max-width:28rem;padding:2rem}
  a.go{display:inline-block;margin-top:1.5rem;padding:.9rem 2.2rem;border-radius:.5rem;
       background:#7c5cff;color:#fff;text-decoration:none;font-weight:600}
  p{color:#9aa4af;line-height:1.5}
</style></head><body><main>
  <h1>🔭 Arra Studio</h1>
  <p>Studio needs its own browser origin, so it opens in a new tab.
     This link carries a single-use pass that expires in five minutes.</p>
  <a class="go" id="go" href="#" target="_blank" rel="opener">Open Studio</a>
  <script>
    document.getElementById('go').href =
      'http://' + location.hostname + ':${PORT}/?studio_auth=${token}';
  </script>
</main></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

function refusalPage(): Response {
  const html = `<!doctype html>
<html><head><meta charset="utf-8"><title>Arra Studio</title></head>
<body style="font-family:system-ui,sans-serif;background:#101418;color:#e6e6e6;
             display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
<main style="text-align:center;max-width:28rem;padding:2rem">
  <h1>🔒 Session required</h1>
  <p style="color:#9aa4af">Open Arra Studio from the Home Assistant sidebar.
     Direct LAN access needs the session that page mints.</p>
</main></body></html>`;
  return new Response(html, { status: 401, headers: { 'content-type': 'text/html; charset=utf-8' } });
}

async function proxy(req: Request, url: URL): Promise<Response> {
  const target = ORACLE_URL + url.pathname + url.search;
  const headers = new Headers(req.headers);
  headers.set('authorization', `Bearer ${ORACLE_API_KEY}`);
  headers.delete('host');
  headers.delete('cookie');
  const upstream = await fetch(target, {
    method: req.method,
    headers,
    body: req.body,
    redirect: 'manual',
  });
  // An absolute redirect to the backend's internal hostname is useless to
  // the browser — fold it back onto this origin.
  const location = upstream.headers.get('location');
  if (location?.startsWith(ORACLE_URL)) {
    const responseHeaders = new Headers(upstream.headers);
    responseHeaders.set('location', location.slice(ORACLE_URL.length) || '/');
    return new Response(upstream.body, { status: upstream.status, headers: responseHeaders });
  }
  return upstream;
}

/**
 * index.html with the bootstrap that points Studio's own host mechanism at
 * this origin, injected ahead of the app bundle.
 */
async function indexPage(): Promise<Response> {
  const raw = await Bun.file(`${DIST}/index.html`).text();
  const bootstrap = `<script>try{localStorage.setItem('oracle:host',location.host)}catch(e){}</script>`;
  const html = raw.includes('<head>')
    ? raw.replace('<head>', `<head>${bootstrap}`)
    : bootstrap + raw;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

const server = Bun.serve({
  port: PORT,
  idleTimeout: 120,
  async fetch(req, srv) {
    const url = new URL(req.url);
    const peer = (srv.requestIP(req)?.address ?? '').replace(/^::ffff:/, '');

    // Ingress traffic: identified by the Supervisor proxy's peer address.
    // X-Ingress-Path is set by Supervisor's own proxy when it strips the
    // /api/hassio_ingress/<token>/ prefix (docs/addon-authoring.md), so its
    // presence is corroborating evidence, not proof by itself — a LAN
    // client could set it on a direct request. Logged unconditionally
    // until the real peer address is confirmed live on thor; the identity
    // check tightens once that's known.
    console.log(`[ingress-probe] peer=${JSON.stringify(peer)} x-ingress-path=${req.headers.get('x-ingress-path')} host=${req.headers.get('host')}`);
    if (peer === INGRESS_PEER || req.headers.has('x-ingress-path')) {
      return launcherPage(mintToken());
    }

    // Token → session exchange on the LAN origin.
    const presented = url.searchParams.get('studio_auth');
    if (presented) {
      sweep(pendingTokens);
      if (pendingTokens.delete(presented)) {
        const value = randomToken().replaceAll(/[^A-Za-z0-9]/g, '');
        sessions.set(value, Date.now() + SESSION_TTL_MS);
        return new Response(null, {
          status: 302,
          headers: {
            location: '/',
            'set-cookie': `studio_session=${value}; Path=/; Max-Age=${SESSION_TTL_MS / 1000}; HttpOnly; SameSite=Lax`,
          },
        });
      }
      return refusalPage();
    }

    if (!hasSession(req)) return refusalPage();

    if (url.pathname.startsWith('/api/') || url.pathname === '/api' || url.pathname.startsWith('/mcp')) {
      return proxy(req, url);
    }

    if (url.pathname === '/' || url.pathname === '/index.html') return indexPage();
    const asset = Bun.file(DIST + url.pathname);
    if (await asset.exists()) return new Response(asset);
    // SPA fallback: unknown paths are client-side routes.
    return indexPage();
  },
});

console.log(`🔭 Arra Studio proxying ${ORACLE_URL} on :${server.port}`);
