// functions/api/create.js — Create item via GitHub API commit

const CATEGORY_PREFIX = { camera: 'CAM', lens: 'LENS', accessory: 'ACCE', misc: 'OTH' };

function normalizeModel(model) {
  return model.replace(/ /g, '-').replace(/[^A-Za-z0-9-]/g, '');
}

function buildItemMd(data, itemId) {
  const costRow = (data.cost_amount && data.cost_note)
    ? `| ${data.date} | ${data.cost_amount} | ${data.cost_note} |\n`
    : '';
  return `---
id: ${itemId}
category: ${data.category}
brand: ${data.brand}
model: ${data.model}
serial_number: "${data.serial_number}"
status: not_started
owner_name: ${data.owner_name}
owner_contact: ${data.owner_contact}
received_date: ${data.date}
delivered_date:
page_password:
---

# 維修描述

${data.description}

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
${costRow}`;
}

async function githubApi(env, path, options = {}) {
  const res = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/${path}`, {
    ...options,
    headers: {
      'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'camera-repair-store-inventory',
      ...options.headers,
    },
  });
  return res;
}

export async function onRequest(context) {
  const { request, env } = context;
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const data = await request.json();
  const branch = env.GITHUB_BRANCH || 'main';

  // Generate ID components
  const prefix = CATEGORY_PREFIX[data.category];
  if (!prefix) {
    return Response.json({ error: 'Invalid category' }, { status: 400 });
  }
  const dateCompact = data.date.replace(/-/g, '');
  const normalizedModel = normalizeModel(data.model);
  const idPrefix = `${prefix}-${dateCompact}-${normalizedModel}`;

  // List existing items in repairs directory to find next sequence
  const dirPath = 'data/repairs';
  const listRes = await githubApi(env, `contents/${dirPath}?ref=${branch}`);
  let seq = 1;
  if (listRes.ok) {
    const entries = await listRes.json();
    for (const entry of entries) {
      if (entry.name.startsWith(idPrefix + '-') && entry.type === 'dir') {
        const num = parseInt(entry.name.slice(idPrefix.length + 1), 10);
        if (num >= seq) seq = num + 1;
      }
    }
  }

  // Retry loop for race conditions
  const MAX_RETRIES = 3;
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    const seqPadded = String(seq + attempt).padStart(3, '0');
    const itemId = `${idPrefix}-${seqPadded}`;
    const filePath = `${dirPath}/${itemId}/item.md`;
    const content = buildItemMd(data, itemId);

    const createRes = await githubApi(env, `contents/${filePath}`, {
      method: 'PUT',
      body: JSON.stringify({
        message: `feat: create ${itemId}`,
        content: btoa(unescape(encodeURIComponent(content))),
        branch,
      }),
    });

    if (createRes.ok) {
      return Response.json({ id: itemId });
    }
    const status = createRes.status;
    if (status !== 409 && status !== 422) {
      const err = await createRes.text();
      return Response.json({ error: `GitHub API error: ${err}` }, { status: 500 });
    }
    // Conflict — try next sequence number
  }

  return Response.json({ error: 'Failed to create item after retries' }, { status: 500 });
}
