// functions/_middleware.js — Shop password gate for admin routes
//
// All routes except /item/* require shop authentication.
// Uses SHOP_PASSWORD env var and a session cookie.

const COOKIE_NAME = 'shop_session';
const COOKIE_MAX_AGE = 86400; // 24 hours

async function verifyToken(token, env) {
  // Simple token verification — token is the hash of password + secret
  const expected = await hashPassword(env.SHOP_PASSWORD);
  return token === expected;
}

async function hashPassword(password) {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, '0')).join('');
}

function getCookie(request, name) {
  const cookies = request.headers.get('Cookie') || '';
  const match = cookies.match(new RegExp(`${name}=([^;]+)`));
  return match ? match[1] : null;
}

function loginPage(error = '') {
  const errorHtml = error ? `<p class="error">${error}</p>` : '';
  return new Response(`<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>登入</title>
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
    <h1>維修系統登入</h1>
    ${errorHtml}
    <form method="POST">
      <input type="password" name="password" placeholder="請輸入密碼" autofocus required>
      <button type="submit">登入</button>
    </form>
  </div>
</body>
</html>`, {
    status: 401,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);

  // Skip auth for customer item pages and static assets (CSS/JS needed by customer pages)
  if (url.pathname.startsWith('/item/') || url.pathname.startsWith('/static/')) {
    return next();
  }

  // Handle login POST
  if (request.method === 'POST' && url.pathname === '/__auth') {
    const formData = await request.formData();
    const password = formData.get('password') || '';

    if (password === env.SHOP_PASSWORD) {
      const token = await hashPassword(password);
      const response = new Response(null, {
        status: 302,
        headers: { 'Location': url.searchParams.get('redirect') || '/' },
      });
      response.headers.set('Set-Cookie',
        `${COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${COOKIE_MAX_AGE}`);
      return response;
    }
    const retryPage = loginPage('密碼錯誤，請重試');
    const retryHtml = (await retryPage.text()).replace(
      'method="POST"',
      `method="POST" action="/__auth?redirect=${encodeURIComponent(url.searchParams.get('redirect') || '/')}"`
    );
    return new Response(retryHtml, {
      status: 401,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  // Check session cookie
  const token = getCookie(request, COOKIE_NAME);
  if (token && await verifyToken(token, env)) {
    return next();
  }

  // Show login page (with redirect back to current page)
  if (request.method === 'GET') {
    const page = loginPage();
    // Rewrite form action to include redirect
    const html = (await page.text()).replace(
      'method="POST"',
      `method="POST" action="/__auth?redirect=${encodeURIComponent(url.pathname)}"`
    );
    return new Response(html, {
      status: 401,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  return new Response('Unauthorized', { status: 401 });
}
