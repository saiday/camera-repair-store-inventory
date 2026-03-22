// functions/item/[id].js — Customer page password gate
//
// Reads published.json manifest, validates per-item password,
// serves customer page on success.

const COOKIE_MAX_AGE = 604800; // 7 days

function getCookie(request, name) {
  const cookies = request.headers.get('Cookie') || '';
  const match = cookies.match(new RegExp(`${name}=([^;]+)`));
  return match ? match[1] : null;
}

async function hashWithSalt(salt, password) {
  const encoder = new TextEncoder();
  const data = encoder.encode(salt + password);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return 'sha256:' + Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, '0')).join('');
}

async function signToken(itemId, env) {
  // HMAC-sign the item ID with SHOP_PASSWORD as key to prevent cookie forgery
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(env.SHOP_PASSWORD), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode('customer:' + itemId));
  return Array.from(new Uint8Array(sig), b => b.toString(16).padStart(2, '0')).join('');
}

async function verifyToken(token, itemId, env) {
  const expected = await signToken(itemId, env);
  return token === expected;
}

function passwordPage(itemId, error = '') {
  const errorHtml = error ? `<p class="error">${error}</p>` : '';
  return new Response(`<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>查看維修進度</title>
  <style>
    body { font-family: -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
    .login { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); width: 320px; }
    h1 { font-size: 1.2rem; margin: 0 0 1rem; }
    input { width: 100%; padding: 0.5rem; margin: 0.5rem 0; box-sizing: border-box; border: 1px solid #ccc; border-radius: 4px; }
    button { width: 100%; padding: 0.5rem; background: #333; color: white; border: none; border-radius: 4px; cursor: pointer; margin-top: 0.5rem; }
    .error { color: #c00; font-size: 0.9rem; }
  </style>
</head>
<body>
  <div class="login">
    <h1>查看維修進度</h1>
    <p>請輸入密碼以查看維修單 ${itemId}</p>
    ${errorHtml}
    <form method="POST">
      <input type="password" name="password" placeholder="請輸入密碼" autofocus required>
      <button type="submit">查看</button>
    </form>
  </div>
</body>
</html>`, {
    status: 401,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

export async function onRequest(context) {
  const { request, env, params } = context;
  const itemId = params.id;

  // Load manifest
  const manifestUrl = new URL('/_data/published.json', request.url);
  const manifestRes = await env.ASSETS.fetch(manifestUrl);
  if (!manifestRes.ok) {
    return new Response('Not Found', { status: 404 });
  }
  const manifest = await manifestRes.json();
  const entry = manifest[itemId];

  if (!entry) {
    return new Response('Not Found', { status: 404 });
  }

  const cookieName = `customer_session_${itemId}`;

  // Handle password POST
  if (request.method === 'POST') {
    const formData = await request.formData();
    const password = formData.get('password') || '';
    const hash = await hashWithSalt(entry.salt, password);

    if (hash === entry.hash) {
      // Serve the customer page with a signed session cookie
      const token = await signToken(itemId, env);
      const pageUrl = new URL(`/customer/${itemId}.html`, request.url);
      const pageRes = await env.ASSETS.fetch(pageUrl);
      const response = new Response(pageRes.body, {
        status: 200,
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
      response.headers.set('Set-Cookie',
        `${cookieName}=${token}; Path=/item/${itemId}; HttpOnly; Secure; SameSite=Strict; Max-Age=${COOKIE_MAX_AGE}`);
      return response;
    }
    return passwordPage(itemId, '密碼錯誤，請重試');
  }

  // Check session cookie (HMAC-signed to prevent forgery)
  const token = getCookie(request, cookieName);
  if (token && await verifyToken(token, itemId, env)) {
    const pageUrl = new URL(`/customer/${itemId}.html`, request.url);
    const pageRes = await env.ASSETS.fetch(pageUrl);
    return new Response(pageRes.body, {
      status: 200,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  // Show password page
  return passwordPage(itemId);
}
