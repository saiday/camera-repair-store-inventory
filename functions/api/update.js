// functions/api/update.js — Update item via GitHub API commit
import { githubApi, findItemPath, applyUpdates } from './_update-helpers.js';

export async function onRequest(context) {
  const { request, env } = context;
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const data = await request.json();
  const branch = env.GITHUB_BRANCH || 'main';
  const itemId = data.id;
  const filePath = findItemPath(itemId);

  // Read current file
  const getRes = await githubApi(env, `contents/${filePath}?ref=${branch}`);
  if (!getRes.ok) {
    return Response.json({ error: 'Item not found' }, { status: 404 });
  }
  const fileData = await getRes.json();
  // GitHub API returns base64 with embedded newlines; strip before decoding
  let content = decodeURIComponent(escape(atob(fileData.content.replace(/\n/g, ''))));
  const sha = fileData.sha;

  // Apply field updates
  content = applyUpdates(content, data);

  // Commit
  const updateRes = await githubApi(env, `contents/${filePath}`, {
    method: 'PUT',
    body: JSON.stringify({
      message: `update: ${itemId}`,
      content: btoa(unescape(encodeURIComponent(content))),
      sha,
      branch,
    }),
  });

  if (updateRes.ok) {
    return Response.json({ ok: true, id: itemId });
  }
  const err = await updateRes.text();
  return Response.json({ error: `GitHub API error: ${err}` }, { status: 500 });
}
