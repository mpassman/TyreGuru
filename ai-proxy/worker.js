/* TyreGuru AI review proxy (Cloudflare Worker).
 *
 * The app sends the review prompt here. This Worker adds the Anthropic API key,
 * which lives only in the Worker's secret settings, and returns the answer.
 * Until ANTHROPIC_API_KEY is set the Worker answers "not_configured" and does nothing else,
 * and the app shows a plain message instead of an AI review.
 *
 * Settings (all optional except the key):
 *   ANTHROPIC_API_KEY  secret  your key. Leave unset to keep the review switched off.
 *   APP_CODE           secret  if set, the app must send the same code (a simple gate against strangers).
 *   MODEL              var     model id, default "claude-sonnet-5-5"
 *   PER_IP_DAILY       var     reviews per device address per day, default 20
 *   DAILY_LIMIT        var     reviews per day in total, default 300
 *   GITHUB_TOKEN       secret  optional. A GitHub token that can create issues in GITHUB_REPO. Leave unset to keep product submissions off.
 *   GITHUB_REPO        var     default "mpassman/TyreGuru"
 *   LIMITS             KV      optional KV namespace so the limits survive restarts. Without it limits are best effort.
 */
const SIGNATURE = 'You are the assistant inside TyreGuru';
const MAX_PROMPT = 12000;
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-TyreGuru-Code',
  'Access-Control-Max-Age': '86400',
};
const memory = new Map();
const clean = (v, n) => String(v == null ? '' : v).replace(/[\u0000-\u001f\u007f`<>\[\]{}|\\]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, n);

/* A rider added a tire or sealant that is not on the list. File it as a GitHub issue for the research job. */
async function submit(request, env) {
  if (!env.GITHUB_TOKEN) return json({ error: 'not_configured', message: 'Product submissions are not switched on yet.' }, 503);
  if (env.APP_CODE && request.headers.get('X-TyreGuru-Code') !== env.APP_CODE) return json({ error: 'bad_code' }, 401);
  let b; try { b = await request.json(); } catch (e) { return json({ error: 'bad_request' }, 400); }
  let item, title;
  if (b && b.kind === 'tire') {
    const brand = clean(b.brand, 40), model = clean(b.model, 60), nominalMm = Math.round(+b.nominalMm);
    if (!brand || !(nominalMm >= 20 && nominalMm <= 90)) return json({ error: 'bad_request', message: 'Tire needs a brand and a width from 20 to 90 mm.' }, 400);
    const maxPsi = +b.maxPsi >= 15 && +b.maxPsi <= 160 ? Math.round(+b.maxPsi) : null;
    item = { kind: 'tire', brand, model, nominalMm, maxPsi, type: ['road', 'gravel', 'mtb'].includes(b.type) ? b.type : null };
    title = `New tire: ${brand} ${model} ${nominalMm} mm`.replace(/\s+/g, ' ');
  } else if (b && b.kind === 'sealant') {
    const name = clean(b.name, 60);
    if (name.length < 2) return json({ error: 'bad_request', message: 'Sealant needs a name.' }, 400);
    item = { kind: 'sealant', name }; title = `New sealant: ${name}`;
  } else return json({ error: 'bad_request' }, 400);

  const day = new Date().toISOString().slice(0, 10);
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  if (!(await bump(env, `sub:${day}:${ip}`, parseInt(env.PER_IP_SUBMIT || '10', 10), 90000)) || !(await bump(env, `suball:${day}`, parseInt(env.DAILY_SUBMIT_LIMIT || '50', 10), 90000)))
    return json({ error: 'limit', message: 'Daily submission limit reached.' }, 429);

  const repo = env.GITHUB_REPO || 'mpassman/TyreGuru';
  const h = { Authorization: `Bearer ${env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json', 'User-Agent': 'tyreguru-service', 'X-GitHub-Api-Version': '2022-11-28' };
  try {
    const q = encodeURIComponent(`repo:${repo} is:issue in:title "${title.replace(/"/g, '')}"`);
    const f = await fetch(`https://api.github.com/search/issues?q=${q}&per_page=1`, { headers: h });
    if (f.ok && (await f.json()).total_count > 0) return json({ ok: true, duplicate: true });
    const r = await fetch(`https://api.github.com/repos/${repo}/issues`, {
      method: 'POST', headers: { ...h, 'content-type': 'application/json' },
      body: JSON.stringify({ title, labels: ['new-product'], body: 'Added by a rider in the TyreGuru app. The research job will look up the manufacturer figures and open a pull request for review.\n\n```json\n' + JSON.stringify(item, null, 1) + '\n```' }),
    });
    if (!r.ok) return json({ error: 'upstream', message: 'GitHub refused the submission.' }, 502);
  } catch (e) { return json({ error: 'upstream', message: 'Could not reach GitHub.' }, 502); }
  return json({ ok: true });
} // fallback counters when no KV namespace is bound

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { 'Content-Type': 'application/json', ...CORS } });

async function bump(env, key, limit, ttl) {
  if (env.LIMITS) {
    const n = parseInt((await env.LIMITS.get(key)) || '0', 10);
    if (n >= limit) return false;
    await env.LIMITS.put(key, String(n + 1), { expirationTtl: ttl });
    return true;
  }
  const now = Date.now();
  for (const [k, v] of memory) if (v.exp < now) memory.delete(k);
  const cur = memory.get(key) || { n: 0, exp: now + ttl * 1000 };
  if (cur.n >= limit) return false;
  cur.n += 1;
  memory.set(key, cur);
  return true;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '/health')) {
      return json({ ok: true, configured: !!env.ANTHROPIC_API_KEY, submissions: !!env.GITHUB_TOKEN, codeRequired: !!env.APP_CODE });
    }
    if (request.method === 'POST' && url.pathname === '/submit') return submit(request, env);
    if (request.method !== 'POST' || url.pathname !== '/review') return json({ error: 'not_found' }, 404);

    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: 'not_configured', message: 'The AI review service has no key yet.' }, 503);
    }
    if (env.APP_CODE && request.headers.get('X-TyreGuru-Code') !== env.APP_CODE) {
      return json({ error: 'bad_code', message: 'The access code is missing or wrong.' }, 401);
    }

    let body;
    try { body = await request.json(); } catch (e) { return json({ error: 'bad_request', message: 'Not JSON.' }, 400); }
    const prompt = body && body.prompt;
    if (typeof prompt !== 'string' || prompt.length < 50 || prompt.length > MAX_PROMPT || !prompt.includes(SIGNATURE)) {
      return json({ error: 'bad_request', message: 'This service only answers TyreGuru reviews.' }, 400);
    }

    const day = new Date().toISOString().slice(0, 10);
    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    const perIp = parseInt(env.PER_IP_DAILY || '20', 10);
    const total = parseInt(env.DAILY_LIMIT || '300', 10);
    if (!(await bump(env, `ip:${day}:${ip}`, perIp, 90000)) || !(await bump(env, `all:${day}`, total, 90000))) {
      return json({ error: 'limit', message: 'Daily AI review limit reached. Try again tomorrow.' }, 429);
    }

    let r;
    try {
      r = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model: env.MODEL || 'claude-sonnet-5-5',
          max_tokens: 500,
          messages: [{ role: 'user', content: prompt }],
        }),
      });
    } catch (e) {
      return json({ error: 'upstream', message: 'Could not reach the AI service.' }, 502);
    }
    if (!r.ok) {
      const busy = r.status === 429 || r.status === 529 || r.status >= 500;
      return json({ error: 'upstream', message: busy ? 'The AI service is busy. Try again in a minute.' : 'The AI service refused the request (check the key).' }, busy ? 503 : 502);
    }
    const data = await r.json();
    const text = (data.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('\n').trim();
    return json({ text });
  },
};
