// Hoodwinkle API: a tiny Neon Function between the browser and Postgres.
//
// It exposes exactly three database functions (hw_day, hw_submit_lie,
// hw_submit_pick) and nothing else. It connects as the low-privilege role
// hw_api, which can call those functions but can't read or write any table.
//
// Environment:
//   HW_DB_URL        connection string for the hw_api role (secret)
//   ALLOWED_ORIGINS  comma-separated browser origins allowed to call the API

const DB_URL = process.env.HW_DB_URL;
const DB_HOST = DB_URL ? new URL(DB_URL).hostname : "";
const ORIGINS = (process.env.ALLOWED_ORIGINS || "").split(",").map(s => s.trim()).filter(Boolean);

// Postgres over HTTPS (Neon's SQL-over-HTTP endpoint), so the function needs no dependencies.
async function sql(query, params) {
  const res = await fetch(`https://${DB_HOST}/sql`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Neon-Connection-String": DB_URL,
      "Neon-Raw-Text-Output": "true",
      "Neon-Array-Mode": "true",
    },
    body: JSON.stringify({ query, params }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(body.message || `database error ${res.status}`);
    err.expected = typeof body.message === "string" && /invalid token|puzzle is closed|lie rejected|own lie|violates check/.test(body.message);
    throw err;
  }
  return body.rows || [];
}

const pgArray = a => "{" + a.map(v => '"' + String(v).replace(/["\\]/g, "\\$&") + '"').join(",") + "}";
const str = (v, max = 200) => { if (typeof v !== "string" || v.length > max) throw bad("bad argument"); return v; };
const day = v => { if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw bad("bad day"); return v; };
const q = v => { if (![0, 1, 2].includes(v)) throw bad("bad question"); return String(v); };
const bad = msg => Object.assign(new Error(msg), { expected: true });

const CALLS = {
  hw_day: {
    sql: "select public.hw_day($1, $2::date)",
    args: a => [str(a.p_token), day(a.p_day)],
    result: rows => JSON.parse(rows[0][0]),
  },
  hw_submit_lie: {
    sql: "select public.hw_submit_lie($1, $2::date, $3::int, $4, $5::boolean)",
    args: a => [str(a.p_token), day(a.p_day), q(a.p_q), str(a.p_lie, 60), a.p_close === true ? "true" : "false"],
    result: () => null,
  },
  hw_submit_pick: {
    sql: "select public.hw_submit_pick($1, $2::date, $3::int, $4, $5::text[])",
    args: a => {
      const shown = Array.isArray(a.p_shown) ? a.p_shown.slice(0, 6).map(s => str(s, 40)) : [];
      return [str(a.p_token), day(a.p_day), q(a.p_q), str(a.p_pick, 40), pgArray(shown)];
    },
    result: () => null,
  },
};

// Per-IP rate limit: 60 calls a minute is plenty for a 3-question daily game.
const hits = new Map();
function limited(ip) {
  const now = Date.now();
  const h = hits.get(ip);
  if (!h || now > h.reset) { hits.set(ip, { n: 1, reset: now + 60_000 }); return false; }
  h.n++;
  if (hits.size > 50_000) hits.clear();
  return h.n > 60;
}

function cors(req) {
  const origin = req.headers.get("origin");
  const allow = origin && (ORIGINS.includes(origin) || ORIGINS.includes("*")) ? origin : "";
  return allow
    ? { "Access-Control-Allow-Origin": allow, "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400", "Vary": "Origin" }
    : { "Vary": "Origin" };
}
const json = (data, status, headers) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...headers } });

export default {
  async fetch(req) {
    const url = new URL(req.url);
    const h = cors(req);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: h });
    if (req.method === "GET" && url.pathname === "/health") {
      try { await sql("select 1", []); return json({ ok: true }, 200, h); }
      catch { return json({ ok: false }, 503, h); }
    }
    const m = url.pathname.match(/^\/rpc\/(hw_day|hw_submit_lie|hw_submit_pick)$/);
    if (req.method !== "POST" || !m) return json({ error: "not found" }, 404, h);
    const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "unknown";
    if (limited(ip)) return json({ error: "slow down" }, 429, h);
    const text = await req.text();
    if (text.length > 4096) return json({ error: "request too large" }, 413, h);
    let args;
    try { args = JSON.parse(text); } catch { return json({ error: "bad json" }, 400, h); }
    const call = CALLS[m[1]];
    try {
      const rows = await sql(call.sql, call.args(args || {}));
      return json(call.result(rows), 200, h);
    } catch (e) {
      if (e.expected) return json({ error: e.message }, 400, h);
      console.error(m[1], e.message);
      return json({ error: "server error" }, 500, h);
    }
  },
};
