// functions/api/update.js — Update item via GitHub API commit

async function githubApi(env, path, options = {}) {
  const res = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/${path}`, {
    ...options,
    headers: {
      'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'camera-repair-inventory',
      ...options.headers,
    },
  });
  return res;
}

function findItemPath(itemId) {
  return `data/repairs/${itemId}/item.md`;
}

function replaceField(content, field, newValue) {
  const regex = new RegExp(`^${field}:.*$`, 'm');
  return content.replace(regex, `${field}: ${newValue}`);
}

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
  let content = decodeURIComponent(escape(atob(fileData.content)));
  const sha = fileData.sha;

  // Apply field updates
  const fields = ['status', 'owner_name', 'owner_contact', 'brand', 'description'];
  for (const field of fields) {
    if (data[field] !== undefined && data[field] !== '') {
      if (field === 'description') {
        // Replace description section
        content = content.replace(
          /(# 維修描述\n\n)[\s\S]*?(\n# 費用紀錄)/,
          `$1${data.description}\n$2`
        );
      } else {
        content = replaceField(content, field, data[field]);
      }
    }
  }

  if (data.serial_number) {
    content = replaceField(content, 'serial_number', `"${data.serial_number}"`);
  }
  if (data.page_password !== undefined) {
    content = replaceField(content, 'page_password', data.page_password);
  }
  if (data.delivered_date) {
    content = replaceField(content, 'delivered_date', data.delivered_date);
  }

  // Clear page_password on delivery
  if (data.status === 'delivered') {
    content = replaceField(content, 'page_password', '');
    if (!data.delivered_date) {
      content = replaceField(content, 'delivered_date', new Date().toISOString().split('T')[0]);
    }
  }

  // Append cost entry
  if (data.cost_amount && data.cost_note) {
    const costDate = data.cost_date || new Date().toISOString().split('T')[0];
    const costLine = `| ${costDate} | ${data.cost_amount} | ${data.cost_note} |`;
    content = content.trimEnd() + '\n' + costLine + '\n';
  }

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
