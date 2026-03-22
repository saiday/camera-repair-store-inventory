# Cloudflare Pages Functions Architecture

This document describes the route-based architecture pattern used to build API and page-serving Workers on Cloudflare Pages Functions. It is written as a reusable reference for future projects.

---

## Overview

Cloudflare Pages Functions uses file-based routing to define request handlers. Files in the `functions/` directory map directly to URL routes. This architecture supports three main patterns:

1. **Middleware** — intercepts all requests to implement global logic (authentication, logging, etc.)
2. **Static routes** — serve pre-built static files from `env.ASSETS` (HTML, CSS, JSON, etc.)
3. **Dynamic routes** — handle API calls or dynamic page generation

---

## File-Based Routing

### Route Mapping

File paths in `functions/` map to URL paths:

| File Path | Matches URL Paths |
|---|---|
| `functions/_middleware.js` | All requests (runs before route handlers) |
| `functions/api/create.js` | `/api/create` |
| `functions/api/update.js` | `/api/update` |
| `functions/item/[id].js` | `/item/{id}` (bracket syntax captures path parameter) |
| `functions/dashboard.js` | `/dashboard` |

### Dynamic Parameters

Brackets `[param]` capture URL segments and pass them to handlers via `context.params`:

```javascript
export async function onRequest(context) {
  const { params } = context;
  const itemId = params.id; // from /item/{id}
}
```

---

## Middleware Pattern

Middleware runs before route handlers and can intercept, modify, or reject requests.

### Structure

```javascript
// functions/_middleware.js
export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);

  // Selectively skip middleware for public routes
  if (url.pathname.startsWith('/public/')) {
    return next();
  }

  // Implement authentication, logging, or request validation
  if (!isAuthenticated(request)) {
    return new Response('Unauthorized', { status: 401 });
  }

  // Pass request to the next handler
  return next();
}
```

### Key Methods

- `next()` — passes the request to the next handler in the chain (the route handler)
- `return Response(...)` — short-circuits the chain and returns immediately

### Common Use Cases

1. **Global authentication** — verify session tokens or API keys before route handlers run
2. **Request validation** — check Content-Type, Content-Length, or CORS headers
3. **Logging** — track all requests for debugging
4. **Rate limiting** — reject or delay requests based on IP or user

---

## Static File Serving with `env.ASSETS`

Cloudflare Pages Functions provide the `env.ASSETS` binding to serve pre-built static files from the Pages output directory.

### Fetching Static Files

Static files are fetched inside route handlers as fetch requests:

```javascript
export async function onRequest(context) {
  const { env, request } = context;

  // Fetch a pre-built HTML file
  const url = new URL('/customer/item-123.html', request.url);
  const response = await env.ASSETS.fetch(url);

  return response;
}
```

### Built-In Response Behavior

`env.ASSETS.fetch()` returns a Response object with headers already set (Content-Type, cache headers, etc.). The response body is a ReadableStream.

```javascript
const response = await env.ASSETS.fetch(url);
console.log(response.status);     // 200 or 404
console.log(response.headers);    // Object with standard HTTP headers
const body = await response.text(); // or .json(), .arrayBuffer(), etc.
```

### Differences from Fetch API

- Only works with **relative paths** within the Pages output directory (`web/`)
- **Ignores middleware** — Workers can read protected files (e.g., `/_data/*`) even though the middleware blocks browser access
- **Cannot fetch external URLs** — only Pages-internal files

### JSON Manifests

A common pattern is to store metadata as JSON in the static output and fetch it in Workers:

```javascript
// build.sh generates web/_data/published.json at build time
// Worker reads it at request time

const manifestUrl = new URL('/_data/published.json', request.url);
const manifestRes = await env.ASSETS.fetch(manifestUrl);
const manifest = await manifestRes.json();

const entry = manifest[itemId];
if (!entry) return new Response('Not Found', { status: 404 });
```

---

## Static vs Dynamic Routes

### Static Routes

Pre-built files served by middleware or the browser:

```
GET /                      → index.html (served by browser/middleware)
GET /dashboard             → dashboard.html (generated at build time)
GET /css/style.css         → style.css (served directly)
GET /_data/items.json      → items.json (protected by middleware, readable by Workers)
```

**Served by:** middleware, CDN cache, or `env.ASSETS` within Workers

**When to use:** content that doesn't change between requests (HTML pages, CSS, JSON metadata)

### Dynamic Routes

Computed at request time by Workers:

```
POST /api/create           → create new item (GitHub API commit)
POST /api/update           → update existing item (GitHub API commit)
GET /item/[id]             → password gate for customer page
```

**Served by:** `functions/` handlers

**When to use:** requests that require authentication, state changes, or logic

---

## Environment Variables

Cloudflare Workers access environment variables via `env`:

```javascript
export async function onRequest(context) {
  const { env } = context;

  console.log(env.SHOP_PASSWORD);
  console.log(env.GITHUB_TOKEN);
  console.log(env.GITHUB_REPO);
}
```

### Configuration

Environment variables are set in `wrangler.toml`:

```toml
[env.production]
vars = { SHOP_PASSWORD = "value", GITHUB_REPO = "owner/repo" }
```

For sensitive values (tokens, passwords), use Cloudflare's Secrets API:

```bash
wrangler secret put GITHUB_TOKEN --env production
```

---

## Build and Deploy Flow

### Local Development

```
1. Edit source files (data/, scripts/, functions/, web/)
2. Run build script: ./scripts/build.sh
3. Generate output: web/*, web/_data/*
4. Test locally with server.py or wrangler dev
```

### Deployment to Cloudflare Pages

```
1. Push changes to GitHub (main branch)
2. Cloudflare Pages webhook triggers build
3. Build command runs: npm run build (or custom script)
4. Build output (web/) deployed to CDN
5. Functions (functions/) deployed automatically
```

### Key Points

- **Build step is mandatory** — static files (HTML, JSON, CSS) must be pre-built
- **Functions are deployed automatically** — no separate deploy step needed
- **Commits trigger rebuilds** — GitHub API mutations (create/update via Workers) push commits that trigger rebuilds
- **Environment variables are set once** — changed in Cloudflare dashboard, not in code

---

## Example: Password-Gated Item Pages

This pattern demonstrates the full architecture:

```javascript
// functions/item/[id].js
export async function onRequest(context) {
  const { request, env, params } = context;
  const itemId = params.id;

  // Step 1: Fetch the manifest (pre-built static JSON)
  const manifestUrl = new URL('/_data/published.json', request.url);
  const manifestRes = await env.ASSETS.fetch(manifestUrl);
  const manifest = await manifestRes.json();

  // Step 2: Check if item is published
  const entry = manifest[itemId];
  if (!entry) return new Response('Not Found', { status: 404 });

  // Step 3: Handle password submission (request mutation)
  if (request.method === 'POST') {
    const formData = await request.formData();
    const password = formData.get('password');
    const hash = await hashPassword(password, entry.salt);

    if (hash === entry.hash) {
      // Step 4: Serve the customer page (fetch static HTML)
      const pageUrl = new URL(`/customer/${itemId}.html`, request.url);
      const pageRes = await env.ASSETS.fetch(pageUrl);
      return pageRes;
    }
    return new Response('Invalid password', { status: 401 });
  }

  // Step 5: For GET requests, show the password form
  return new Response(passwordFormHtml(itemId), {
    status: 401,
    headers: { 'Content-Type': 'text/html' },
  });
}
```

**Layers in this example:**

1. **Middleware** — not involved (customer pages don't require shop auth)
2. **Static JSON** — manifest read via `env.ASSETS.fetch()`
3. **Dynamic logic** — password validation in Worker
4. **Static HTML** — customer page served via `env.ASSETS.fetch()`

---

## Summary

| Component | Purpose | Location |
|---|---|---|
| Middleware | Global authentication, request validation | `functions/_middleware.js` |
| Route handlers | API endpoints, dynamic content | `functions/api/*.js`, `functions/[param].js` |
| Static files | Pre-built HTML, CSS, JSON | `web/` (served by middleware or fetched via `env.ASSETS`) |
| `env.ASSETS` | Worker reads static files at request time | Inside function handlers |
| Environment variables | API keys, passwords, configuration | Set in Cloudflare dashboard or `wrangler.toml` |
| Build step | Generate static output before deployment | Bash or npm scripts |

This architecture separates concerns: middleware handles auth, route handlers implement logic, and `env.ASSETS` bridges Workers and the static site.
