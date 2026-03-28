// functions/api/batch-update.js — Batch update items via single GitHub API commit
import { githubApi, findItemPath, applyUpdates } from './_update-helpers.js';

const MAX_BATCH_SIZE = 50;

function decodeContent(base64) {
  // GitHub API returns base64 with embedded newlines; strip before decoding
  return decodeURIComponent(escape(atob(base64.replace(/\n/g, ''))));
}

function encodeContent(text) {
  return btoa(unescape(encodeURIComponent(text)));
}

export async function onRequest(context) {
  const { request, env } = context;
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const body = await request.json();
  const updates = body.updates;

  // --- Validation ---
  if (!Array.isArray(updates) || updates.length === 0) {
    return Response.json({ error: 'updates must be a non-empty array' }, { status: 400 });
  }
  if (updates.length > MAX_BATCH_SIZE) {
    return Response.json({ error: `Too many updates (max ${MAX_BATCH_SIZE})` }, { status: 400 });
  }
  const ids = updates.map(u => u.id);
  if (new Set(ids).size !== ids.length) {
    return Response.json({ error: 'Duplicate IDs in batch' }, { status: 400 });
  }

  const branch = env.GITHUB_BRANCH || 'main';

  // --- Step 1: Get current HEAD ref ---
  const refRes = await githubApi(env, `git/ref/heads/${branch}`);
  if (!refRes.ok) {
    return Response.json({ error: 'Failed to get branch ref' }, { status: 500 });
  }
  const refData = await refRes.json();
  const headSha = refData.object.sha;

  // --- Step 2: Get HEAD commit's tree SHA ---
  const commitRes = await githubApi(env, `git/commits/${headSha}`);
  if (!commitRes.ok) {
    return Response.json({ error: 'Failed to get HEAD commit' }, { status: 500 });
  }
  const commitData = await commitRes.json();
  const baseTreeSha = commitData.tree.sha;

  // --- Step 3: Read all item files in parallel ---
  const readResults = await Promise.all(
    updates.map(async (entry) => {
      const filePath = findItemPath(entry.id);
      const res = await githubApi(env, `contents/${filePath}?ref=${branch}`);
      if (!res.ok) {
        return { id: entry.id, error: true };
      }
      const fileData = await res.json();
      return { id: entry.id, filePath, content: decodeContent(fileData.content), entry };
    })
  );

  const succeeded = readResults.filter(r => !r.error);
  const failed = readResults.filter(r => r.error).map(r => r.id);

  if (succeeded.length === 0) {
    return Response.json({ error: 'All items failed to read', failed }, { status: 400 });
  }

  // --- Step 4: Apply field updates ---
  let treeEntries;
  try {
    treeEntries = succeeded.map(item => {
      const updatedContent = applyUpdates(item.content, item.entry);
      return {
        path: item.filePath,
        mode: '100644',
        type: 'blob',
        content: updatedContent,
      };
    });
  } catch (e) {
    return Response.json({ error: e.message }, { status: 400 });
  }

  // --- Step 5: Create tree ---
  const treeRes = await githubApi(env, 'git/trees', {
    method: 'POST',
    body: JSON.stringify({ base_tree: baseTreeSha, tree: treeEntries }),
  });
  if (!treeRes.ok) {
    const err = await treeRes.text();
    return Response.json({ error: `Failed to create tree: ${err}` }, { status: 500 });
  }
  const treeData = await treeRes.json();

  // --- Step 6: Create commit ---
  const succeededIds = succeeded.map(s => s.id);
  const message = `update: ${succeededIds.join(', ')}`;
  const newCommitRes = await githubApi(env, 'git/commits', {
    method: 'POST',
    body: JSON.stringify({
      message,
      tree: treeData.sha,
      parents: [headSha],
    }),
  });
  if (!newCommitRes.ok) {
    const err = await newCommitRes.text();
    return Response.json({ error: `Failed to create commit: ${err}` }, { status: 500 });
  }
  const newCommitData = await newCommitRes.json();

  // --- Step 7: Update ref ---
  const updateRefRes = await githubApi(env, `git/refs/heads/${branch}`, {
    method: 'PATCH',
    body: JSON.stringify({ sha: newCommitData.sha, force: false }),
  });
  if (!updateRefRes.ok) {
    return Response.json({ error: 'Concurrent update conflict, please retry' }, { status: 409 });
  }

  // --- Response ---
  if (failed.length > 0) {
    return Response.json({ ok: false, error: 'Some items failed', succeeded: succeededIds, failed });
  }
  return Response.json({ ok: true, ids: succeededIds });
}
