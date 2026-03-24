// functions/api/_update-helpers.js — Shared helpers for update endpoints

export function githubApi(env, path, options = {}) {
  return fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/${path}`, {
    ...options,
    headers: {
      'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'camera-repair-store-inventory',
      ...options.headers,
    },
  });
}

export function findItemPath(itemId) {
  const parts = itemId.split('-');
  const dateStr = parts[1]; // e.g. "20260305"
  const year = dateStr.substring(0, 4);
  const month = dateStr.substring(4, 6);
  return `data/repairs/${year}/${month}/${itemId}/item.md`;
}

export function replaceField(content, field, newValue) {
  const regex = new RegExp(`^${field}:.*$`, 'm');
  if (regex.test(content)) {
    return content.replace(regex, `${field}: ${newValue}`);
  }
  const closingIdx = content.indexOf('\n---', 3);
  if (closingIdx !== -1) {
    return content.slice(0, closingIdx) + `\n${field}: ${newValue}` + content.slice(closingIdx);
  }
  return content;
}

export function applyUpdates(content, data) {
  const fields = ['status', 'owner_name', 'owner_contact', 'brand', 'description'];
  for (const field of fields) {
    if (data[field] !== undefined && data[field] !== '') {
      if (field === 'description') {
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
  if (data.status === 'delivered') {
    content = replaceField(content, 'page_password', '');
    if (!data.delivered_date) {
      content = replaceField(content, 'delivered_date', new Date().toISOString().split('T')[0]);
    }
  }
  if (data.cost_amount && data.cost_note) {
    const costDate = data.cost_date || new Date().toISOString().split('T')[0];
    const costLine = `| ${costDate} | ${data.cost_amount} | ${data.cost_note} |`;
    content = content.trimEnd() + '\n' + costLine + '\n';
  }

  return content;
}
