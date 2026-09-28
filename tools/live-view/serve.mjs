#!/usr/bin/env node
// Live read-only view of the Device UI against a Mujina API (rdsmujina-env #90).
//
//   node tools/live-view/serve.mjs <device-ui ui/ dir>
//
// Serves the UI's static files at /ui/ and proxies ONLY the Device UI's four
// GETs to the upstream Mujina API. The upstream forward passes any method, so
// this allowlist is the gate. One upstream request per path per short TTL is
// shared by every open tab, so viewers do not multiply the unit's load. When
// no Mujina window runs, upstream refuses: the API answers 503 "offline".
//
// Env: LIVE_PORT (8787), LIVE_HOST (0.0.0.0), LIVE_UPSTREAM
//      (http://127.0.0.1:17785), LIVE_AUTH ("user:pass" turns on basic auth),
//      LIVE_MAX_HOURS (4: the process exits after that),
//      LIVE_SHARES_LOG (a redacted share stream; see sharesFromLog),
//      LIVE_SAMPLES_FILE (chip-share samples kept across restarts, JSONL),
//      LIVE_KEEP_HOURS (12: how far back samples are kept),
//      LIVE_RT_PRIOR (a previous process's /live/realtime reply, carried over),
//      LIVE_HARNESS_DIR (the mujina_bzm2 window's live psu.log, mcu.log, case.json),
//      LIVE_SUMMARY_MS (5000: asic-summary sampling), LIVE_SUMMARIES_FILE.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const uiRoot = path.resolve(process.argv[2] || '.');
const PORT = Number(process.env.LIVE_PORT || 8787);
const HOST = process.env.LIVE_HOST || '0.0.0.0';
const UP = new URL(process.env.LIVE_UPSTREAM || 'http://127.0.0.1:17785');
const AUTH = process.env.LIVE_AUTH ? 'Basic ' + Buffer.from(process.env.LIVE_AUTH).toString('base64') : null;
const MAX_MS = Number(process.env.LIVE_MAX_HOURS || 4) * 3600e3;
const SHARES_LOG = process.env.LIVE_SHARES_LOG || '';
const SAMPLE_MS = Number(process.env.LIVE_SAMPLE_MS || 5000);
const SAMPLES_FILE = process.env.LIVE_SAMPLES_FILE || '';
const KEEP_MS = Number(process.env.LIVE_KEEP_HOURS || 12) * 3600e3;
const RT_PRIOR = process.env.LIVE_RT_PRIOR || '';
const HARNESS = process.env.LIVE_HARNESS_DIR || '';
const RT_WINDOWS = Object.fromEntries((process.env.LIVE_RT_WINDOWS || '1m:60,5m:300,15m:900').split(',').map((x) => x.split(':')).map(([k, v]) => [k, Number(v)]));
// Ronald, 2026-09-28: the selector sets how far back the chart looks as well
// as the averaging window; the longest looks back over the whole run (0 = from
// the run's start). The first window gets 30 min, the second 3 h.
const LOOKBACK = Object.fromEntries(Object.keys(RT_WINDOWS).map((k, i, all) => [k, i === all.length - 1 && all.length > 1 ? 0 : [1800e3, 3 * 3600e3][i] ?? 0]));

const ALLOW = [/^\/api\/v0\/miner$/, /^\/api\/v0\/health$/, /^\/api\/v0\/boards\/[^/]+\/bzm2\/(asic-summary|chain-summary)$/];
const MINER_TTL = Number(process.env.LIVE_MINER_TTL_MS || 1500);
const TTL = (p) => (p.endsWith('/miner') ? MINER_TTL : p.endsWith('/health') ? 2000 : 4000);
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.json': 'application/json', '.txt': 'text/plain; charset=utf-8', '.png': 'image/png' };
const counts = { static: 0, api: 0, upstream: 0, offline: 0, refused: 0 };
const cache = new Map(); // path -> { at, res } and/or { pending }

function fetchUpstream(p) {
  counts.upstream++;
  return new Promise((resolve) => {
    const req = http.get({ host: UP.hostname, port: UP.port, path: p, timeout: 8000 }, (r) => {
      const chunks = [];
      r.on('data', (c) => chunks.push(c));
      r.on('end', () => resolve({ status: r.statusCode, type: r.headers['content-type'] || 'application/json', body: Buffer.concat(chunks) }));
    });
    const offline = (why) => {
      counts.offline++;
      resolve({ status: 503, type: 'application/json', body: Buffer.from(JSON.stringify({ error: 'offline', detail: `Mujina API not answering (${why}): no Mujina window running` })) });
    };
    req.on('timeout', () => { req.destroy(); offline('timeout'); });
    req.on('error', (e) => offline(e.code || e.message));
  });
}

function shared(p) {
  const c = cache.get(p);
  if (c?.res && Date.now() - c.at < TTL(p)) return Promise.resolve(c.res);
  if (c?.pending) return c.pending;
  const pending = fetchUpstream(p).then((res) => {
    cache.set(p, { at: Date.now(), res });
    if (res.status === 200 && p.endsWith('/bzm2/asic-summary')) recordSummary(p, res.body); // once per upstream reply
    return res;
  });
  cache.set(p, { ...c, pending });
  return pending;
}

// Stopgap until Mujina's /miner carries the pool's share counts (mujina-bzm2-dev#211).
// The Mujina port project streams Mujina's share lines, redacted, to a file:
//   "# window log (re)read <UTC>; counts restart here"  (on every (re)connect,
//   followed by a replay of the window), "HH:MM:SS accepted job_id=..." and
//   "HH:MM:SS rejected job_id=... reason=...". Counts run from the LAST marker.
function sharesFromLog() {
  let text;
  try { text = fs.readFileSync(SHARES_LOG, 'utf8'); } catch { return null; }
  const lines = text.split('\n');
  let start = 0;
  lines.forEach((l, i) => { if (l.startsWith('# window log')) start = i + 1; });
  let accepted = 0, rejected = 0, last = null; const reasons = {};
  for (const l of lines.slice(start)) {
    const m = l.match(/^(\d\d:\d\d:\d\d) (accepted|rejected)\b(?:.*\breason=(\S+))?/);
    if (!m) continue;
    last = m[1];
    if (m[2] === 'accepted') accepted++;
    else { rejected++; const r = m[3] || 'unknown'; reasons[r] = (reasons[r] || 0) + 1; }
  }
  return { accepted, rejected, reasons, last };
}

// Hashrate history from the pool's accepted shares (Ronald, 2026-09-28): the
// dashboard's chart holds only what one browser saw since it loaded, and
// Mujina keeps no history yet (mujina-bzm2-dev#194). Each accepted share at
// difficulty D is D x 2^32 hashes, so a window of W seconds holding n shares
// averages n x D x 2^32 / W. D is the current /miner difficulty, assumed to
// hold for the whole window. Computed here, never in the browser.
let lastDifficulty = null;
const WINDOWS = { '1m': 60, '5m': 300, '15m': 900 };
function hashrateHistory() {
  let text;
  try { text = fs.readFileSync(SHARES_LOG, 'utf8'); } catch { return null; }
  // Every marker's segment counts, so the history reaches the log's first
  // line. A marker replays its window, so a share line is counted as many
  // times as the one segment that holds it most, never once per replay.
  const most = new Map();
  let seg = new Map(), day = new Date().toISOString().slice(0, 10);
  const close = () => { for (const [k, n] of seg) most.set(k, Math.max(most.get(k) || 0, n)); seg = new Map(); };
  for (const l of text.split('\n')) {
    const mk = l.match(/^# window log \(re\)read (\d{4}-\d\d-\d\d)T/);
    if (mk) { close(); day = mk[1]; continue; }
    const m = l.match(/^(\d\d:\d\d:\d\d) accepted\b/);
    if (m) { const k = `${day}T${m[1]}Z ${l}`; seg.set(k, (seg.get(k) || 0) + 1); }
  }
  close();
  const times = [...most].flatMap(([k, n]) => Array(n).fill(Date.parse(k.slice(0, 20)))).sort((a, b) => a - b);
  if (!times.length || !lastDifficulty) return { difficulty: lastDifficulty, first: times[0] ?? null, windows: {} };
  // Runs: a gap of 10 min with no share (about e^-50 at this rate) is no
  // Mujina window, not a measured zero, so the line breaks there (null).
  const GAP = 600e3, runs = [];
  for (const t of times) {
    const r = runs[runs.length - 1];
    if (r && t - r[1] <= GAP) r[1] = t; else runs.push([t, t]);
  }
  runs[runs.length - 1][1] = Math.min(Date.now(), times[times.length - 1] + 900e3);
  const step = 30e3, first = times[0], last = times[times.length - 1];
  const windows = {};
  for (const [k, w] of Object.entries(WINDOWS)) {
    const pts = [];
    runs.forEach(([a, b], ri) => {
      if (ri) pts.push([Math.floor(a / step) * step - 1, null, 0]);
      for (let t = Math.floor(a / step) * step; t <= b; t += step) {
        const n = times.filter((x) => x > t - w * 1e3 && x <= t).length;
        pts.push([t, Math.round((n * lastDifficulty * 2 ** 32) / w), n]);
      }
    });
    windows[k] = pts;
  }
  return { difficulty: lastDifficulty, first, last, shares: times.length, step_ms: step, windows, runs: runs.length,
    source: "pool-accepted shares x difficulty, counted by the live view from Mujina's log; unit clock, UTC" };
}

// Real-time hashrate from chip shares (the Mujina port project's recipe,
// 2026-09-28). miner.hashrate is a 5-minute sliding average by construction
// (scheduler.rs:73), so the dashboard's line is smooth however often it
// polls. Each thread's share target is set for about one share a second at
// its own estimate (scheduler.rs:194), so a thread's accepted chip shares
// over W seconds, times its estimate, give its hashrate over W. The
// counters are boards[0].bzm2_tuning.asics[].results.accepted (not
// 'decoded', which counts below-target results). A restart (uptime or a
// counter going down) starts a new segment; nothing differences across it.
const samples = []; // { t, seg, up, acc: [..], hs: [..], mujina }
let threadNames = [];
let boardNames = [];
let segment = 0;
// Samples outlive the process (JSONL), so a restart keeps the run's history.
if (SAMPLES_FILE) {
  try {
    for (const l of fs.readFileSync(SAMPLES_FILE, 'utf8').split('\n')) {
      let s; try { s = JSON.parse(l); } catch { continue; }
      if (!(s?.t > Date.now() - KEEP_MS) || !Array.isArray(s.acc)) continue;
      const prev = samples[samples.length - 1];
      if (prev && (s.up < prev.up || s.acc.some((v, k) => v < (prev.acc[k] ?? 0)))) segment++;
      s.seg = segment; samples.push(s);
    }
  } catch { /* no file yet */ }
}
// Points a previous process computed, before its samples were kept: shown
// only before this process's first sample, never mixed into a window.
let prior = { windows: {}, mujina: [] };
if (RT_PRIOR) { try { prior = JSON.parse(fs.readFileSync(RT_PRIOR, 'utf8')); } catch { /* none */ } }
function sampleMiner(body) {
  let m;
  try { m = JSON.parse(body); } catch { return; }
  // The history's difficulty, even when no browser polls /miner (only /live/ open).
  const d0 = Array.isArray(m?.sources) ? m.sources[0]?.difficulty : undefined;
  if (Number.isFinite(d0)) lastDifficulty = d0;
  const b = Array.isArray(m.boards) ? m.boards[0] : null;
  const threads = Array.isArray(b?.threads) ? b.threads : [];
  const asics = Array.isArray(b?.bzm2_tuning?.asics) ? b.bzm2_tuning.asics : [];
  if (!threads.length || !asics.length) return;
  const acc = threads.map(() => 0);
  for (const a of asics) {
    const n = a?.results?.accepted;
    if (Number.isFinite(n) && acc[a.thread_index] != null) acc[a.thread_index] += n;
  }
  const s = { t: Date.now(), up: m.uptime_secs, acc, hs: threads.map((x) => x.hashrate), mujina: m.hashrate };
  // Mujina's own fan readings per board, for the page's history (Ronald, 2026-09-28).
  s.fans = {};
  for (const bd of Array.isArray(m.boards) ? m.boards : []) {
    if (bd?.name && Array.isArray(bd.fans)) s.fans[bd.name] = bd.fans.map((f) => [f?.name, f?.rpm ?? null, f?.percent ?? null]);
  }
  boardNames = Object.keys(s.fans).length ? Object.keys(s.fans) : (Array.isArray(m.boards) ? m.boards.map((x) => x?.name).filter(Boolean) : []);
  threadNames = threads.map((x, i) => String(x?.name ?? `thread ${i}`));
  const prev = samples[samples.length - 1];
  if (prev && (s.up < prev.up || s.acc.some((v, k) => v < (prev.acc[k] ?? 0)))) segment++;
  s.seg = segment;
  if (prev && prev.up === s.up && prev.acc.every((v, k) => v === s.acc[k])) return; // no new publish
  samples.push(s);
  if (SAMPLES_FILE) { try { fs.appendFileSync(SAMPLES_FILE, JSON.stringify({ t: s.t, up: s.up, acc: s.acc, hs: s.hs, mujina: s.mujina, fans: s.fans }) + '\n'); } catch { /* disk: keep serving */ } }
  while (samples.length && samples[0].t < s.t - KEEP_MS) samples.shift();
}
function realtime() {
  const windows = {};
  for (const [k, w] of Object.entries(RT_WINDOWS)) {
    const pts = [];
    let prevT = null;
    for (let i = 0, j = 0; i < samples.length; i++) {
      const si = samples[i];
      while (j < i && (samples[j].seg !== si.seg || si.t - samples[j + 1].t >= w * 1e3)) j++;
      const sj = samples[j];
      // A point's span stays near its window: never 0.8x short, never 1.5x long
      // (after an outage the nearest older sample can be minutes back).
      if (sj.seg !== si.seg || si.t - sj.t < w * 1e3 * 0.8 || si.t - sj.t > w * 1e3 * 1.5) continue;
      // An outage breaks the line (#21): no point is drawn across unsampled time.
      if (prevT != null && si.t - prevT > 3 * SAMPLE_MS) pts.push([Math.round((prevT + si.t) / 2), null, 0, null, null]);
      prevT = si.t;
      const dt = (si.t - sj.t) / 1e3;
      let h = 0, n = 0;
      const per = si.acc.map((v, t) => { const d = v - (sj.acc[t] ?? 0); n += d; const x = Math.round((d / dt) * (si.hs[t] ?? 0)); h += x; return x; });
      // J/TH: the same window's mean wall-side input power over its chip-share total.
      const w0 = HARNESS ? powerMean(si.t - w * 1e3, si.t) : null;
      pts.push([si.t, h, n, per, w0 != null && h > 0 ? Math.round((w0 / (h / 1e12)) * 10) / 10 : null]);
    }
    const t0 = samples[0]?.t ?? Infinity;
    windows[k] = [...(prior.windows?.[k] || []).filter((x) => x[0] < t0), ...pts];
  }
  const t0 = samples[0]?.t ?? Infinity, lastS = samples[samples.length - 1];
  // The run's start: the latest sample's time less Mujina's uptime.
  return { windows, mujina: [...(prior.mujina || []).filter((x) => x[0] < t0), ...samples.map((x) => [x.t, x.mujina])],
    run_start: lastS ? lastS.t - lastS.up * 1000 : null, last_uptime_secs: lastS?.up ?? null,
    threads: threadNames, lookback_ms: LOOKBACK,
    carried_over_until: (prior.windows && Object.values(prior.windows).some((a) => a.length)) ? t0 : null,
    segments: segment + 1, samples: samples.length,
    source: "chip shares: accepted per thread (bzm2_tuning.asics[].results.accepted) x that thread's estimate, sampled by the live view" };
}
// asic-summary aggregates per board, recorded once per upstream reply (the
// page's polls and this sampler share the cache), kept for KEEP_MS on disk.
const SUMMARIES_FILE = process.env.LIVE_SUMMARIES_FILE || (SAMPLES_FILE ? SAMPLES_FILE.replace(/\.jsonl$/, '') + '-summaries.jsonl' : '');
const sums = []; // { t, b, die: [min, mean, max, spread], cov: [reporting, configured, suppressed, neverSeen] }
if (SUMMARIES_FILE) {
  try {
    for (const l of fs.readFileSync(SUMMARIES_FILE, 'utf8').split('\n')) {
      let x; try { x = JSON.parse(l); } catch { continue; }
      if (x?.t > Date.now() - KEEP_MS) sums.push(x);
    }
  } catch { /* none yet */ }
}
function recordSummary(p, body) {
  let d; try { d = JSON.parse(body); } catch { return; }
  const b = decodeURIComponent(p.split('/')[4] || '');
  const die = d?.board?.die_temperature_c, cov = d?.board?.coverage;
  if (!b || (!die && !cov)) return;
  const x = { t: Date.now(), b, die: die ? [die.min, die.mean, die.max, die.spread] : null,
    cov: cov ? [cov.asics_reporting, cov.asics_configured, cov.asics_value_suppressed ?? null, cov.asics_never_seen ?? null] : null };
  sums.push(x);
  while (sums.length && sums[0].t < x.t - KEEP_MS) sums.shift();
  if (SUMMARIES_FILE) { try { fs.appendFileSync(SUMMARIES_FILE, JSON.stringify(x) + '\n'); } catch { /* keep serving */ } }
}
const SUMMARY_MS = Number(process.env.LIVE_SUMMARY_MS || 5000); // the page's own asic-summary cadence
setInterval(() => { for (const b of boardNames) shared(`/api/v0/boards/${encodeURIComponent(b)}/bzm2/asic-summary`); }, SUMMARY_MS).unref();

// The page's history (Ronald, 2026-09-28: "it should have the ability to pull
// in the current state from the server into the browser"), in the page's own
// ring shapes, since a time, at most the page's 15-minute buffer. Past samples
// only; a gap in the hashrate is a null, never bridged.
const HISTORY_MS = 900e3;
function pageHistory(since) {
  const t0 = Math.max(Number.isFinite(since) ? since : 0, Date.now() - HISTORY_MS);
  const out = { source: 'live view: its own /miner samples and asic-summary replies; power from the harness', hashrate: [], fans: {}, die: {}, coverage: {}, power: [] };
  let prev = null;
  for (const x of samples) {
    if (x.t <= t0) continue;
    if (prev != null && x.t - prev > 3 * SAMPLE_MS) out.hashrate.push([Math.round((prev + x.t) / 2), null]);
    prev = x.t;
    if (Number.isFinite(x.mujina)) out.hashrate.push([x.t, x.mujina]);
    for (const [b, f] of Object.entries(x.fans || {})) (out.fans[b] ||= []).push([x.t, f]);
    if (HARNESS && Number.isFinite(x.mujina) && x.mujina > 0) {
      const w5 = powerMean(x.t - 300e3, x.t), w = powerMean(x.t - 5000, x.t);
      if (w5 != null && w != null) out.power.push([x.t, Math.round((w5 / (x.mujina / 1e12)) * 10) / 10, Math.round(w)]);
    }
  }
  for (const x of sums) {
    if (x.t <= t0) continue;
    if (x.die) (out.die[x.b] ||= []).push([x.t, ...x.die]);
    if (x.cov) (out.coverage[x.b] ||= []).push([x.t, ...x.cov]);
  }
  return out;
}

const sampleNow = () => shared('/api/v0/miner').then((r) => { if (r.status === 200) sampleMiner(r.body); });
setInterval(sampleNow, SAMPLE_MS).unref();
sampleNow(); // the difficulty and a first sample at start, not SAMPLE_MS later

// Merge the counts into /miner's first source, only when Mujina's own keys are
// absent: Mujina's counters take over by themselves once they ship.
function withShares(r) {
  if ((!SHARES_LOG && !HARNESS) || r.status !== 200) return r;
  let m;
  try { m = JSON.parse(r.body); } catch { return r; }
  const s0 = Array.isArray(m.sources) ? m.sources[0] : null;
  if (Number.isFinite(s0?.difficulty)) lastDifficulty = s0.difficulty;
  // The harness's facts ride in their own object, never as Mujina's keys.
  if (HARNESS) m.harness = harnessNow(m);
  const c = SHARES_LOG && s0 && s0.shares_accepted == null ? sharesFromLog() : null;
  if (c) Object.assign(s0, { shares_accepted: c.accepted, shares_rejected: c.rejected, shares_rejected_by_reason: c.reasons,
    shares_counted_by: "live view: counted from Mujina's log", shares_last_at: c.last ? `${c.last} UTC` : null });
  return { ...r, body: Buffer.from(JSON.stringify(m)) };
}

// ---- The harness streams (Ronald, 2026-09-28: J/TH and the worker on the
// harness view). The mujina_bzm2 window tails its own psu.tsv and mcu.tsv
// into psu.log and mcu.log (utc, recv_utc, [phase,] elapsed_s, signal, value)
// and writes case.json. A (re)connect replays the files after a marker, so a
// row is keyed by (utc, signal) and counted once. A blank utc (the handover
// gap) is never placed. Only the signals shown are kept, for KEEP_MS.
const KEEP_SIGNALS = /^(psu\.input_power_raw|hwmon\d+\.rpm|pwmchip\d+\.duty_pct|board\d+\.(inlet|outlet)_c)$/;
const series = new Map(); // signal -> Map(tMs -> value)
const tails = new Map(); // file -> { off, rest }
function pollHarness() {
  for (const f of ['psu.log', 'mcu.log']) {
    const file = path.join(HARNESS, f);
    let st; try { st = fs.statSync(file); } catch { continue; }
    const t = tails.get(file) || { off: 0, rest: '' };
    if (st.size < t.off) { t.off = 0; t.rest = ''; } // replaced: read again; the keys dedupe
    if (st.size > t.off) {
      const fd = fs.openSync(file, 'r');
      const buf = Buffer.alloc(st.size - t.off);
      fs.readSync(fd, buf, 0, buf.length, t.off); fs.closeSync(fd);
      t.off = st.size;
      const lines = (t.rest + buf.toString('utf8')).split('\n');
      t.rest = lines.pop();
      for (const l of lines) {
        if (!l || l[0] === '#') continue;
        const c = l.split('\t');
        const utc = c[0], sig = c[c.length - 2], v = Number(c[c.length - 1]);
        if (!utc || !KEEP_SIGNALS.test(sig) || !Number.isFinite(v)) continue;
        const ms = Date.parse(utc);
        if (!Number.isFinite(ms)) continue;
        if (!series.has(sig)) series.set(sig, new Map());
        series.get(sig).set(ms, v);
      }
    }
    tails.set(file, t);
  }
  const cut = Date.now() - KEEP_MS;
  for (const m of series.values()) for (const k of m.keys()) { if (k < cut) m.delete(k); else break; }
  // Input power, sorted with prefix sums: a window's mean is two binary searches.
  const pm = series.get('psu.input_power_raw');
  const pts = pm ? [...pm].sort((a, b) => a[0] - b[0]) : [];
  powerIdx = { ts: pts.map((x) => x[0]), cum: pts.reduce((a, x) => (a.push((a[a.length - 1] || 0) + x[1]), a), []) };
}
let powerIdx = { ts: [], cum: [] };
const firstAbove = (ts, t) => { let lo = 0, hi = ts.length; while (lo < hi) { const mid = (lo + hi) >> 1; if (ts[mid] > t) hi = mid; else lo = mid + 1; } return lo; };
function powerMean(t0, t1) { // mean input W over (t0, t1], or null
  const { ts, cum } = powerIdx; const i = firstAbove(ts, t0), j = firstAbove(ts, t1);
  if (j <= i) return null;
  return (cum[j - 1] - (i ? cum[i - 1] : 0)) / (j - i);
}
function latest(sig) {
  const m = series.get(sig); if (!m || !m.size) return null;
  let bt = -Infinity, bv = null; for (const [t, v] of m) if (t > bt) { bt = t; bv = v; }
  return { t: bt, v: bv };
}
function meanOver(sig, t0, t1) {
  const m = series.get(sig); if (!m) return null;
  let n = 0, sum = 0; for (const [t, v] of m) if (t > t0 && t <= t1) { n++; sum += v; }
  return n ? { mean: sum / n, n } : null;
}
function harnessNow(m) {
  let c = {}; try { c = JSON.parse(fs.readFileSync(path.join(HARNESS, 'case.json'), 'utf8')); } catch { /* none yet */ }
  const p = latest('psu.input_power_raw');
  // J/TH over one window: the 5-min mean input power over Mujina's 5-min sliding hashrate.
  const pm = p ? meanOver('psu.input_power_raw', p.t - 300e3, p.t) : null;
  const ths = Number.isFinite(m?.hashrate) && m.hashrate > 0 ? m.hashrate / 1e12 : null;
  const fans = {}, duty = {}, temps = {};
  for (const sig of series.keys()) {
    const x = latest(sig); if (!x) continue;
    if (sig.endsWith('.rpm')) fans[sig.split('.')[0]] = x.v;
    else if (sig.endsWith('.duty_pct')) duty[sig.split('.')[0]] = x.v;
    else if (sig.startsWith('board')) temps[sig] = x.v;
  }
  return {
    case: c.case ?? null, run: c.run ?? null, worker: c.worker ?? null, pool: c.pool ?? null,
    input_w: p ? p.v : null, input_w_at: p ? new Date(p.t).toISOString() : null,
    j_per_th: pm && ths ? Math.round((pm.mean / ths) * 10) / 10 : null,
    power_source: "wall-side: the PSU's input power (harness psu.log), including the control board, fans and conversion losses; not chip-side",
    j_per_th_basis: "5-min mean input power over Mujina's 5-min sliding hashrate",
    fans, duty, temps, counted_by: 'live view: from the mujina_bzm2 window\'s live streams',
  };
}
if (HARNESS) { pollHarness(); setInterval(pollHarness, 5000).unref(); }

function send(res, status, type, body) {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  if (AUTH && req.headers.authorization !== AUTH) {
    res.writeHead(401, { 'www-authenticate': 'Basic realm="RDS live view"' });
    return res.end('authentication required');
  }
  let p;
  try { p = decodeURIComponent(new URL(req.url, 'http://x').pathname); } catch { return send(res, 400, 'text/plain', 'bad path'); }
  if (p.startsWith('/api/')) {
    counts.api++;
    if (!ALLOW.some((re) => re.test(p))) { counts.refused++; return send(res, 403, 'text/plain', 'not on the read-only allowlist'); }
    if (req.method !== 'GET') { counts.refused++; return send(res, 405, 'text/plain', 'read-only: GET only'); }
    const r = await shared(p);
    const out = p === '/api/v0/miner' ? withShares(r) : r;
    return send(res, out.status, out.type, out.body);
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'text/plain', 'GET only');
  if (p === '/live/realtime') return send(res, 200, 'application/json', JSON.stringify(realtime()));
  if (p === '/ui/history.json') {
    const since = Number(new URL(req.url, 'http://x').searchParams.get('since'));
    return send(res, 200, 'application/json', JSON.stringify(pageHistory(since)));
  }
  if (p === '/live/hashrate-history') {
    const h = SHARES_LOG ? hashrateHistory() : null;
    return h ? send(res, 200, 'application/json', JSON.stringify(h)) : send(res, 404, 'text/plain', 'no share stream');
  }
  if (p === '/live' || p === '/live/') return send(res, 200, 'text/html; charset=utf-8', HISTORY_PAGE);
  if (p === '/' || p === '/ui') { res.writeHead(302, { location: '/ui/' }); return res.end(); }
  if (!p.startsWith('/ui/')) return send(res, 404, 'text/plain', 'not found');
  const file = path.resolve(uiRoot, '.' + (p.slice(3) === '/' ? '/index.html' : p.slice(3)));
  if (file !== uiRoot && !file.startsWith(uiRoot + path.sep)) return send(res, 404, 'text/plain', 'not found');
  fs.readFile(file, (err, buf) => {
    if (err) return send(res, 404, 'text/plain', 'not found');
    counts.static++;
    send(res, 200, MIME[path.extname(file)] || 'application/octet-stream', req.method === 'HEAD' ? '' : buf);
  });
});

server.listen(PORT, HOST, () => console.log(`live-view: http://${HOST}:${PORT}/ui/ -> ${UP.href} (auth ${AUTH ? 'on' : 'off'}, exits in ${MAX_MS / 3600e3} h)`));
// One summary line a minute, never one per request.
setInterval(() => console.log(`live-view: ${new Date().toISOString()} ${JSON.stringify(counts)}`), 60e3).unref();
setTimeout(() => { console.log('live-view: time limit reached, exiting'); process.exit(0); }, MAX_MS).unref();

// The history page: one SVG line chart, 1m / 5m / 15m averages over the run.
const HISTORY_PAGE = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Hashrate history</title>
<style>
:root{--bg:#f4f1ec;--surface:#fff;--ink:#1a1917;--muted:#6b665e;--line:#0f9fb8;--grid:#d9d4cb;--b0:#6d5bd0;--b1:#1f8a70;--b2:#b5651d}
@media (prefers-color-scheme:dark){:root{--bg:#0f1317;--surface:#151a1f;--ink:#d6dde3;--muted:#9aa4ad;--line:#35c4dc;--grid:#2a343c;--b0:#9b8cf0;--b1:#3fc49e;--b2:#e0975a}}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 ui-monospace,Menlo,monospace}
main{max-width:1100px;margin:0 auto;padding:16px}
.card{background:var(--surface);border:1px solid var(--grid);border-radius:10px;padding:14px}
button{font:inherit;border:1px solid var(--grid);background:var(--surface);color:var(--ink);border-radius:6px;padding:3px 10px;cursor:pointer}
button[aria-pressed=true]{background:var(--ink);color:var(--surface)}
.muted{color:var(--muted)} svg{width:100%;height:auto;display:block} a{color:inherit}
</style></head><body><main>
<p><a href="/ui/">&larr; dashboard</a></p>
<h1 style="font-size:18px;margin:0 0 6px">Hashrate per board, stacked, from chip shares</h1>
<p class="muted" id="rtsrc">loading&hellip;</p>
<div class="card" style="margin-bottom:18px"><div style="margin-bottom:8px" role="group" aria-label="Real-time window">
<button data-rt="1m" aria-pressed="true">1m · last 30 min</button> <button data-rt="5m">5m · last 3 h</button> <button data-rt="15m">15m · whole run</button>
<span class="muted" id="rtstat" style="margin-left:10px"></span></div>
<svg id="rt" viewBox="0 0 1000 300" role="img" aria-label="Real-time hashrate chart"></svg>
<p class="muted" style="margin:6px 0 0">The button picks the averaging window and how far back to look (Ronald, 2026-09-28); 15m shows the whole run from its start, ramp included. Stacked areas: each board's accepted chip shares over the window &times; that thread's estimate (about one share a second per thread), so roughly &plusmn;1/&radic;n for n shares (&plusmn;7.5% at 1 min). The line on top is their total. Dashed: Mujina's own figure, a 5-minute sliding average. Dotted: from the run's start until chip sampling began, the pool-accepted-share average over the same window, from the history below. A Mujina restart starts a new series.</p><p id="legend" class="muted" style="margin:4px 0 0"></p></div>
<h1 style="font-size:18px;margin:0 0 6px">Efficiency, wall-side J/TH</h1>
<p class="muted" id="jstat">loading&hellip;</p>
<div class="card" style="margin-bottom:18px"><svg id="jt" viewBox="0 0 1000 200" role="img" aria-label="J/TH chart"></svg>
<p class="muted" style="margin:6px 0 0">Each point: the window's mean PSU input power over the window's chip-share total, on the same time axis and window as the chart above. Wall-side: the supply's input includes the control board, fans and conversion losses, so this is not chip-side. Lower is more efficient. Source: the mujina_bzm2 window's live psu stream. Private view: no public claims before the first 48-hour run.</p></div>
<h1 style="font-size:18px;margin:0 0 6px">Hashrate history, from the pool's accepted shares</h1>
<p class="muted" id="src">loading&hellip;</p>
<div class="card"><div style="margin-bottom:8px" role="group" aria-label="Averaging window">
<button data-w="1m">1m average</button> <button data-w="5m">5m average</button> <button data-w="15m" aria-pressed="true">15m average</button>
<span class="muted" id="stat" style="margin-left:10px"></span></div>
<svg id="c" viewBox="0 0 1000 380" role="img" aria-label="Hashrate history chart"></svg></div>
<p class="muted">Each accepted share at difficulty D stands for D &times; 2<sup>32</sup> hashes, so a window of W seconds holding n shares averages n &times; D &times; 2<sup>32</sup> / W. Few shares per window means a noisy average: roughly &plusmn;1/&radic;n. The current difficulty is assumed to have held for the whole window. Times are the unit's clock, UTC. Private view: not for publication.</p>
</main><script>
let data=null,w='15m';
const fmt=(h)=>h>=1e15?(h/1e15).toFixed(2)+' PH/s':h>=1e12?(h/1e12).toFixed(2)+' TH/s':h>=1e9?(h/1e9).toFixed(2)+' GH/s':h+' H/s';
const hm=(t)=>new Date(t).toISOString().slice(11,16);
// A null value breaks the line: between runs nothing was measured.
const pathOf=(a,X,Y)=>{let d='',pen=false;for(const x of a){if(x[1]==null){pen=false;continue}d+=(pen?'L':'M')+X(x[0]).toFixed(1)+' '+Y(x[1]).toFixed(1)+' ';pen=true}return d};
function draw(){const c=document.getElementById('c');c.innerHTML='';if(!data||!data.windows[w]){return}
const p=data.windows[w];if(!p.length)return;const W=1000,H=380,L=100,B=30,T=10;
const t0=p[0][0],t1=p[p.length-1][0],mx=Math.max(...p.map(x=>x[1]||0))*1.1||1;
const X=(t)=>L+(W-L-10)*(t-t0)/Math.max(1,t1-t0),Y=(v)=>H-B-(H-B-T)*v/mx;
let g='';for(let i=0;i<=4;i++){const v=mx*i/4;g+='<line x1="'+L+'" x2="'+(W-10)+'" y1="'+Y(v)+'" y2="'+Y(v)+'" stroke="var(--grid)"/><text x="'+(L-6)+'" y="'+(Y(v)+4)+'" text-anchor="end" fill="var(--muted)" font-size="11">'+fmt(v)+'</text>'}
const nt=6;for(let i=0;i<=nt;i++){const t=t0+(t1-t0)*i/nt;g+='<text x="'+X(t)+'" y="'+(H-10)+'" text-anchor="'+(i===0?'start':i===nt?'end':'middle')+'" fill="var(--muted)" font-size="11">'+hm(t)+'</text>'}
c.innerHTML=g+'<path d="'+pathOf(p,X,Y)+'" fill="none" stroke="var(--line)" stroke-width="2"/>';
const lastp=p[p.length-1];document.getElementById('stat').textContent='latest '+w+': '+fmt(lastp[1])+' from '+lastp[2]+' shares';}
async function load(){try{const r=await fetch('/live/hashrate-history',{cache:'no-store'});if(!r.ok)throw new Error(r.status);data=await r.json();
if(!data.shares)setTimeout(load,3000);document.getElementById('src').textContent=data.shares?(data.shares+' accepted shares since '+hm(data.first)+' UTC in '+data.runs+' run'+(data.runs===1?'':'s')+' (the line breaks between runs), difficulty '+data.difficulty+'. Source: '+data.source+'.'):'no accepted shares in this window yet';draw();drawRT()}
catch(e){document.getElementById('src').textContent='history unavailable ('+e.message+')'}}
document.querySelectorAll('button[data-w]').forEach(b=>b.onclick=()=>{w=b.dataset.w;document.querySelectorAll('button[data-w]').forEach(x=>x.setAttribute('aria-pressed',x===b));draw()});
let rt=null,rw='1m';
function drawRT(){const c=document.getElementById('rt');c.innerHTML='';if(!rt||!rt.windows[rw])return;const p=rt.windows[rw];if(!p.length){document.getElementById('rtstat').textContent='collecting: the window needs '+rw+' of samples';return}
// Look-back per button (0 = the whole run). Before chip sampling began: the pool-share average, from the run's start.
const lb=(rt.lookback_ms||{})[rw]||0;const tEnd=p[p.length-1][0];const tMin=lb?tEnd-lb:(rt.run_start??p[0][0]);
const q=p.filter(x=>x[0]>=tMin);if(!q.length)return;
const rs=rt.run_start!=null&&rt.run_start<q[0][0]&&rt.run_start>=tMin?rt.run_start:(tMin<q[0][0]?tMin:null);const pw=rw;
const pre=rs!=null&&data&&data.windows&&data.windows[pw]?data.windows[pw].filter(x=>x[0]>=rs&&x[0]<q[0][0]):[];
const t0=rs!=null?rs:q[0][0];
const mu=[];for(const x of rt.mujina.filter(x=>x[0]>=t0&&x[1]!=null)){if(mu.length&&x[0]-mu[mu.length-1][0]>30000)mu.push([x[0],null]);mu.push(x)} // an outage breaks this line too (#99)
const W=1000,H=300,L=100,B=30,T=10;
const t1=tEnd,mx=Math.max(...q.map(x=>x[1]||0),...mu.map(x=>x[1]||0),...pre.map(x=>x[1]||0))*1.1||1;
const X=(t)=>L+(W-L-10)*(t-t0)/Math.max(1,t1-t0),Y=(v)=>H-B-(H-B-T)*v/mx;
let g='';for(let i=0;i<=4;i++){const v=mx*i/4;g+='<line x1="'+L+'" x2="'+(W-10)+'" y1="'+Y(v)+'" y2="'+Y(v)+'" stroke="var(--grid)"/><text x="'+(L-6)+'" y="'+(Y(v)+4)+'" text-anchor="end" fill="var(--muted)" font-size="11">'+fmt(v)+'</text>'}
const nt=5;for(let i=0;i<=nt;i++){const t=t0+(t1-t0)*i/nt;g+='<text x="'+X(t)+'" y="'+(H-10)+'" text-anchor="'+(i===0?'start':i===nt?'end':'middle')+'" fill="var(--muted)" font-size="11">'+new Date(t).toISOString().slice(11,19)+'</text>'}
const path=(a)=>a.map((x,i)=>(i?'L':'M')+X(x[0]).toFixed(1)+' '+Y(x[1]).toFixed(1)).join(' ');
// Stacked per-board areas (points carry [t, total, n, [per board]]); the total line on top.
const runs=[];let cur=[];for(const x of q){if(x[1]==null||!Array.isArray(x[3])){if(cur.length)runs.push(cur);cur=[];}else cur.push(x)}if(cur.length)runs.push(cur);
const lastOwn=runs.length?runs[runs.length-1]:[];const nb=lastOwn.length?lastOwn[lastOwn.length-1][3].length:0;let bands='';
for(const own of runs)for(let b=nb-1;b>=0;b--){const top=own.map(x=>[x[0],x[3].slice(0,b+1).reduce((a,v)=>a+v,0)]);const bot=own.map(x=>[x[0],x[3].slice(0,b).reduce((a,v)=>a+v,0)]);
let d='';top.forEach((x,i)=>{d+=(i?'L':'M')+X(x[0]).toFixed(1)+' '+Y(x[1]).toFixed(1)});for(let i=bot.length-1;i>=0;i--)d+='L'+X(bot[i][0]).toFixed(1)+' '+Y(bot[i][1]).toFixed(1);
bands+='<path d="'+d+'Z" fill="var(--b'+(b%3)+')" fill-opacity="0.45" stroke="none"/>'}
c.innerHTML=g+bands+(pre.length?'<path d="'+pathOf(pre,X,Y)+'" fill="none" stroke="var(--line)" stroke-dasharray="2 3" stroke-width="2"/>':'')+(mu.length?'<path d="'+pathOf(mu,X,Y)+'" fill="none" stroke="var(--muted)" stroke-dasharray="6 4" stroke-width="1.5"/>':'')+'<path d="'+pathOf(q,X,Y)+'" fill="none" stroke="var(--ink)" stroke-width="2"/>';
const l=q.filter(x=>x[1]!=null).pop()||q[q.length-1];document.getElementById('rtstat').textContent='latest '+rw+' total: '+fmt(l[1])+' from '+l[2]+' shares (\u00b1'+(l[2]?Math.round(100/Math.sqrt(l[2])):'?')+'%)';
drawJT(q,t0,t1);
const names=rt.threads||[];document.getElementById('legend').innerHTML=(Array.isArray(l[3])?l[3]:[]).map((v,i)=>'<span style="display:inline-block;width:10px;height:10px;background:var(--b'+(i%3)+');opacity:.7;margin:0 4px 0 10px;vertical-align:middle"></span>Board '+i+(names[i]?' ('+names[i].replace(/[<>&]/g,'')+')':'')+': '+fmt(v)).join('')}
function drawJT(q,t0,t1){const c=document.getElementById('jt');c.innerHTML='';const p=q.filter(x=>x[4]!=null);const st=document.getElementById('jstat');
if(!p.length){st.textContent='no J/TH yet: needs the harness power stream and chip-share windows';return}
const W=1000,H=200,L=100,B=30,T=10;let lo=Math.min(...p.map(x=>x[4])),hi=Math.max(...p.map(x=>x[4]));const pad=(hi-lo)*0.1||1;lo=Math.max(0,lo-pad);hi=hi+pad;
const X=(t)=>L+(W-L-10)*(t-t0)/Math.max(1,t1-t0),Y=(v)=>H-B-(H-B-T)*(v-lo)/(hi-lo);
let g='';for(let i=0;i<=3;i++){const v=lo+(hi-lo)*i/3;g+='<line x1="'+L+'" x2="'+(W-10)+'" y1="'+Y(v)+'" y2="'+Y(v)+'" stroke="var(--grid)"/><text x="'+(L-6)+'" y="'+(Y(v)+4)+'" text-anchor="end" fill="var(--muted)" font-size="11">'+v.toFixed(1)+' J/TH</text>'}
c.innerHTML=g+'<path d="'+pathOf(p.map(x=>[x[0],x[4]]),X,Y)+'" fill="none" stroke="var(--line)" stroke-width="2"/>';
const l=p[p.length-1];st.textContent='latest '+rw+': '+l[4].toFixed(1)+' J/TH (wall-side), '+new Date(l[0]).toISOString().slice(11,19)+' UTC'}
async function loadRT(){try{const r=await fetch('/live/realtime',{cache:'no-store'});rt=await r.json();document.getElementById('rtsrc').textContent=(rt.run_start!=null?'Mujina run since '+new Date(rt.run_start).toISOString().slice(11,19)+' UTC. ':'')+rt.samples+' samples'+(rt.carried_over_until?' (earlier points carried over from the previous live-view process)':'')+'; source: '+rt.source+'.';drawRT()}catch(e){document.getElementById('rtsrc').textContent='real-time unavailable ('+e.message+')'}}
document.querySelectorAll('button[data-rt]').forEach(b=>b.onclick=()=>{rw=b.dataset.rt;document.querySelectorAll('button[data-rt]').forEach(x=>x.setAttribute('aria-pressed',x===b));drawRT()});
load();setInterval(load,30000);loadRT();setInterval(loadRT,5000);
</script></body></html>`;
