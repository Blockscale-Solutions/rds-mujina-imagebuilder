# The live read-only view (#90): only the Device UI's four GETs reach the unit,
# viewers share one upstream request, and a stopped Mujina reads as offline.
LV="$(repo_root)/tools/live-view/serve.mjs"

check() { # scenario -> the checker's output (one "key=value" per line)
    node --input-type=module - "$LV" "$1" <<'JS' 2>&1
import http from 'node:http'; import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const [lv, scenario] = process.argv.slice(2);
const free = () => new Promise((r) => { const s = http.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => r(p)); }); });
const ui = fs.mkdtempSync(path.join(os.tmpdir(), 'lv-ui-')); fs.writeFileSync(path.join(ui, 'index.html'), '<p>ui</p>');
let hits = 0;
const upPort = await free(), port = await free();
const log = path.join(ui, 'shares.log');
fs.writeFileSync(log, '# window log (re)read 2026-09-28T10:00:00Z; counts restart here\n10:01:00 accepted job_id=a\n10:02:00 rejected job_id=b reason=old\n# window log (re)read 2026-09-28T14:35:38Z; counts restart here\n14:36:15 accepted job_id=c\n14:36:16 accepted job_id=d\n14:37:07 rejected job_id=e reason=stale-prevblk\n' + (scenario === 'history' ? '# window log (re)read 2026-09-28T14:40:00Z; counts restart here\n14:36:15 accepted job_id=c\n14:36:16 accepted job_id=d\n' : ''));
// The harness streams (Mujina port project, 2026-09-28): psu.log and mcu.log
// replay after a marker; a blank utc (the handover gap) is never placed.
const hdir = path.join(ui, 'harness'); fs.mkdirSync(hdir);
const now0 = Date.now(), iso = (ms) => new Date(Math.floor(ms / 1000) * 1000).toISOString().replace('.000Z', 'Z');
let psu = '# utc\trecv_utc\telapsed_s\tsignal\tvalue\n# (re)read x; rows restart here\n';
for (let i = 0; i < 400; i++) psu += `${iso(now0 - (400 - i) * 1000)}\t-\t${i}\tpsu.input_power_raw\t3600\n`;
psu += '# (re)read y; rows restart here\n';
for (let i = 0; i < 415; i++) psu += `${iso(now0 - (400 - i) * 1000)}\t-\t${i}\tpsu.input_power_raw\t3600\n`;
psu += `\t-\t1\tpsu.input_power_raw\t99999\n`;
fs.writeFileSync(path.join(hdir, 'psu.log'), psu);
fs.writeFileSync(path.join(hdir, 'mcu.log'), `# utc\trecv_utc\tphase\telapsed_s\tsignal\tvalue\n${iso(now0 - 2000)}\t-\thold\t1\thwmon0.rpm\t6700\n`);
fs.writeFileSync(path.join(hdir, 'case.json'), JSON.stringify({ case: 'MJ-TEST-00', run: 'R1', worker: 'mujina', pool: 'pool.invalid:3333' }));
let reqN = 0; let gapN = 0;
const rtBody = () => { reqN++; const acc = scenario === 'realtime-reset' && reqN > 6 ? reqN : 10 * reqN;
  return { uptime_secs: scenario === 'realtime-reset' && reqN > 6 ? reqN : 100 + reqN, hashrate: 3e12, sources: [{ name: 'pool', difficulty: 1000 }],
    boards: [{ name: 'b', fans: [{ name: 'fan0', rpm: 6780, percent: 100 }], threads: [0, 1, 2].map((i) => ({ name: `t${i}`, hashrate: 1e12 })),
      bzm2_tuning: { asics: [0, 1, 2].flatMap((t) => [{ thread_index: t, results: { accepted: acc } }, { thread_index: t }]) } }] }; };
const minerBody = scenario.startsWith('history') ? { sources: [{ name: 'pool', difficulty: 1000 }] } : scenario === 'shares-native' ? { sources: [{ name: 'pool', shares_accepted: 5, shares_rejected: 0 }] } : { sources: [{ name: 'pool' }] };
const up = http.createServer((q, s) => { hits++; setTimeout(() => {
  if (scenario === 'history-feed' && q.url.endsWith('/asic-summary')) { s.setHeader('content-type', 'application/json');
    return s.end(JSON.stringify({ board: { die_temperature_c: { min: 60, mean: 70, max: 80, spread: 20 }, coverage: { asics_configured: 300, asics_reporting: 299, asics_value_suppressed: 0, asics_never_seen: 1 } } })); }
  if (scenario === 'realtime-gap' && q.url === '/api/v0/miner') { gapN = (gapN || 0) + 1; if (gapN > 5 && gapN <= 12) { reqN++; s.statusCode = 502; return s.end('{}'); } } s.setHeader('content-type', 'application/json'); s.end(JSON.stringify((scenario.startsWith('realtime') || scenario === 'harness' || scenario === 'history-feed') && q.url === '/api/v0/miner' ? rtBody() : (scenario.startsWith('shares') || scenario.startsWith('history')) && q.url === '/api/v0/miner' ? minerBody : { path: q.url, method: q.method })); }, 150); });
if (scenario !== 'down') await new Promise((r) => up.listen(upPort, '127.0.0.1', r));
const env = { ...process.env, LIVE_PORT: String(port), LIVE_HOST: '127.0.0.1', LIVE_UPSTREAM: `http://127.0.0.1:${upPort}`, LIVE_AUTH: scenario === 'auth' ? 'call:pw' : '', LIVE_SAMPLE_MS: '300', LIVE_SUMMARY_MS: '400', LIVE_RT_WINDOWS: '1s:1', LIVE_MINER_TTL_MS: scenario.startsWith('realtime') || scenario === 'harness' || scenario === 'history-feed' ? '50' : '1500', LIVE_SHARES_LOG: scenario.startsWith('shares') || scenario.startsWith('history') ? log : '', LIVE_SAMPLES_FILE: path.join(ui, 'samples.jsonl'), LIVE_HARNESS_DIR: scenario === 'harness' ? hdir : '', LIVE_RT_PRIOR: scenario === 'realtime' ? path.join(ui, 'prior.json') : '' };
if (scenario === 'realtime') fs.writeFileSync(path.join(ui, 'prior.json'), JSON.stringify({ windows: { '1s': [[1000, 5e12, 9]] }, mujina: [[1000, 4e12]] }));
let srv = spawn('node', [lv, ui], { env, stdio: 'ignore' });
const base = `http://127.0.0.1:${port}`;
for (let i = 0; i < 50; i++) { try { await fetch(base + '/ui/'); break; } catch { await new Promise((r) => setTimeout(r, 100)); } }
const st = async (u, o) => { const r = await fetch(base + u, o); return [r.status, await r.text()]; };
const out = [];
try {
  if (scenario === 'basic') {
    const [s1, b1] = await st('/api/v0/miner'); out.push(`miner=${s1} ${JSON.parse(b1).method}`);
    out.push(`post=${(await st('/api/v0/miner', { method: 'POST' }))[0]}`);
    out.push(`diag=${(await st('/api/v0/boards/b0/bzm2/dts-vs', {}))[0]}`);
    out.push(`traversal=${(await st('/ui/..%2f..%2f..%2fetc%2fpasswd'))[0]}`);
    out.push(`page=${(await st('/ui/'))[0]}`);
    hits = 0; await Promise.all([st('/api/v0/health'), st('/api/v0/health'), st('/api/v0/health')]);
    out.push(`coalesced_upstream_hits=${hits}`);
  } else if (scenario === 'down') {
    const [s, b] = await st('/api/v0/miner'); out.push(`down=${s} ${JSON.parse(b).error}`);
  } else if (scenario.startsWith('realtime') && scenario !== 'realtime-gap') {
    await new Promise((r) => setTimeout(r, 4000));
    const h = JSON.parse((await st('/live/realtime'))[1]);
    const pts = h.windows['1s'];
    out.push(`pts=${pts.length > 3 ? 'many' : pts.length} segments=${h.segments} mujina=${h.mujina.length > 3 ? 'many' : h.mujina.length}`);
    const vals = pts.filter((p) => p[1] !== null); // a null is a break, drawn as a gap (#21)
    out.push(`positive=${vals.length > 0 && vals.every((p) => p[1] > 0)} finite=${vals.every((p) => Number.isFinite(p[1]))}`);
    out.push(`runstart=${Math.abs(h.run_start - (Date.now() - h.last_uptime_secs * 1000)) < 5000 ? 'ok' : h.run_start}`);
    // Ronald 2026-09-28: the boards stacked with the total on top; the selector sets the look-back.
    const own = pts.filter((q) => Array.isArray(q[3]));
    out.push(`perthread=${own.length > 0 && own.every((q) => q[3].length === 3 && Math.abs(q[3].reduce((x, y) => x + y, 0) - q[1]) <= 3)} threads=${JSON.stringify(h.threads)}`);
    out.push(`lookback=${JSON.stringify(h.lookback_ms)}`);
    if (scenario === 'realtime') {
      out.push(`prior=${pts[0][0] === 1000 && h.mujina[0][0] === 1000}`);
      // A restart of the live view keeps what it sampled (#90 follow-up).
      const before = h.samples;
      srv.kill(); await new Promise((r) => srv.on('exit', r));
      srv = spawn('node', [lv, ui], { env, stdio: 'ignore' });
      for (let i = 0; i < 50; i++) { try { await fetch(base + '/ui/'); break; } catch { await new Promise((r) => setTimeout(r, 100)); } }
      const h2 = JSON.parse((await st('/live/realtime'))[1]);
      out.push(`kept=${h2.samples >= before && before > 3}`);
    }
  } else if (scenario === 'realtime-gap') {
    await new Promise((r) => setTimeout(r, 7000));
    const h = JSON.parse((await st('/live/realtime'))[1]);
    const pts = h.windows['1s'];
    const t = pts.filter((q) => q[1] !== null).map((q) => q[0]);
    let spanned = false; for (let i = 1; i < pts.length; i++) if (pts[i][1] !== null && pts[i - 1][1] !== null && pts[i][0] - pts[i - 1][0] > 900) spanned = true;
    out.push(`break=${pts.some((q) => q[1] === null)} spanned=${spanned} points=${t.length > 3}`);
  } else if (scenario === 'history-feed') {
    // Ronald 2026-09-28: the page pulls what it missed from the server.
    await new Promise((r) => setTimeout(r, 3000));
    const h = JSON.parse((await st('/ui/history.json?since=0'))[1]);
    const hr = (h.hashrate || []).filter((x) => x[1] !== null);
    out.push(`hashrate=${hr.length > 3} fans=${(h.fans?.b || []).length > 3 && h.fans.b[0][1][0][1] === 6780} die=${(h.die?.b || []).length > 0 && h.die.b[0][2] === 70} coverage=${(h.coverage?.b || []).length > 0 && h.coverage.b[0][1] === 299}`);
    const last = hr[hr.length - 1][0];
    const h2 = JSON.parse((await st(`/ui/history.json?since=${last}`))[1]);
    out.push(`since=${(h2.hashrate || []).every((x) => x[0] > last)}`);
  } else if (scenario === 'harness') {
    await new Promise((r) => setTimeout(r, 4000));
    const m = JSON.parse((await st('/api/v0/miner'))[1]);
    const h = m.harness || {};
    out.push(`worker=${h.worker} case=${h.case} input_w=${h.input_w} jth=${h.j_per_th} basis=${/wall-side/.test(h.power_source || '')}`);
    out.push(`fan0=${h.fans && h.fans.hwmon0}`);
    // J/TH over time: each window's mean input power over that window's chip-share total.
    const rt = JSON.parse((await st('/live/realtime'))[1]);
    const pts = rt.windows['1s'] || [];
    out.push(`jth_series=${pts.length > 0 && pts.every((q) => q[4] === null || (Number.isFinite(q[4]) && q[4] > 0)) && pts.some((q) => Number.isFinite(q[4]))}`);
  } else if (scenario === 'history-unpolled') {
    // No browser polls /miner: the sampler alone must supply the difficulty.
    await new Promise((r) => setTimeout(r, 1500));
    out.push(`diff=${JSON.parse((await st('/live/hashrate-history'))[1]).difficulty}`);
  } else if (scenario === 'history') {
    await st('/api/v0/miner');
    const h = JSON.parse((await st('/live/hashrate-history'))[1]);
    const one = h.windows['1m'].find((pt) => pt[0] === Date.parse('2026-09-28T14:37:00Z'));
    out.push(`diff=${h.difficulty} first=${new Date(h.first).toISOString()} pts=${h.windows['1m'].length} at1437_n=${one && one[2]} at1437_hs=${one && one[1]}`);
    out.push(`gap=${h.windows['1m'].some((pt) => pt[1] === null)} ingap=${h.windows['1m'].some((pt) => pt[0] > Date.parse('2026-09-28T10:30:00Z') && pt[0] < Date.parse('2026-09-28T14:00:00Z') && pt[1] !== null)}`);
    out.push(`page=${(await st('/live/'))[0]}`);
  } else if (scenario.startsWith('shares')) {
    const m = JSON.parse((await st('/api/v0/miner'))[1]).sources[0];
    out.push(`acc=${m.shares_accepted} rej=${m.shares_rejected} reasons=${JSON.stringify(m.shares_rejected_by_reason || null)} by=${m.shares_counted_by || 'mujina'} last=${m.shares_last_at || '-'}`);
  } else if (scenario === 'auth') {
    out.push(`noauth=${(await st('/ui/'))[0]}`);
    out.push(`auth=${(await st('/ui/', { headers: { authorization: 'Basic ' + Buffer.from('call:pw').toString('base64') } }))[0]}`);
  }
} catch (e) { out.push(`error=${e.message}`); }
srv.kill(); up.close(); console.log(out.join('\n'));
JS
}

test_only_the_four_gets_pass_and_viewers_share_one_upstream_request() {
    local out; out=$(check basic)
    assert_contains "$out" "miner=200 GET"
    assert_contains "$out" "post=405"
    assert_contains "$out" "diag=403"
    assert_contains "$out" "traversal=404"
    assert_contains "$out" "page=200"
    assert_contains "$out" "coalesced_upstream_hits=1"
}

test_a_stopped_mujina_reads_as_offline() {
    assert_contains "$(check down)" "down=503 offline"
}

test_basic_auth_is_enforced_when_set() {
    local out; out=$(check auth)
    assert_contains "$out" "noauth=401"
    assert_contains "$out" "auth=200"
}

test_share_counts_from_the_last_window_marker_are_merged_into_miner_and_labelled() {
    local out; out=$(check shares)
    assert_contains "$out" 'acc=2 rej=1 reasons={"stale-prevblk":1}'
    assert_contains "$out" "by=live view: counted from Mujina's log"
    assert_contains "$out" "last=14:37:07 UTC"
}

test_mujina_s_own_share_counts_are_never_overridden() {
    assert_contains "$(check shares-native)" "acc=5 rej=0 reasons=null by=mujina"
}

test_hashrate_history_averages_accepted_shares_over_each_window() {
    # Shares at 14:36:15 and 14:36:16 (accepted) and 14:37:07 (rejected): the
    # 1-minute point at 14:37:00 holds 2 accepted, so 2 x 1000 x 2^32 / 60.
    local out; out=$(check history)
    # Every window marker's shares count, from the log's first line; a replay
    # after a later marker is not counted twice. Between runs the line breaks
    # (null): no shares logged is not a measured zero.
    assert_contains "$out" "diff=1000 first=2026-09-28T10:01:00.000Z"
    assert_contains "$out" "at1437_n=2 at1437_hs=$(( (2 * 1000 * 4294967296 + 30) / 60 ))"
    assert_contains "$out" "gap=true ingap=false"
    assert_contains "$out" "page=200"
}

test_realtime_hashrate_from_chip_share_counters_per_window() {
    local out; out=$(check realtime)
    assert_contains "$out" "pts=many segments=1 mujina=many"
    assert_contains "$out" "positive=true finite=true"
    assert_contains "$out" "runstart=ok"
    assert_contains "$out" 'perthread=true threads=["t0","t1","t2"]'
    assert_contains "$out" 'lookback={"1s":1800000}'
    assert_contains "$out" "prior=true"
    assert_contains "$out" "kept=true"
}

test_a_restart_starts_a_new_series_and_never_differences_across_it() {
    local out; out=$(check realtime-reset)
    assert_contains "$out" "segments=2"
    assert_contains "$out" "positive=true finite=true"
}

test_history_needs_no_browser_polling_miner_for_its_difficulty() {
    # After a restart only /live/ may be open; it never fetches /miner itself.
    assert_contains "$(check history-unpolled)" "diff=1000"
}

test_harness_worker_power_and_j_per_th_reach_the_dashboard_labelled() {
    # Ronald 2026-09-28: J/TH and the current worker on the harness view.
    # Synthetic fixture, fictional case MJ-TEST-00: 3,600 W over 3 TH/s = 1,200 J/TH; the replay counts once.
    local out; out=$(check harness)
    assert_contains "$out" "worker=mujina case=MJ-TEST-00 input_w=3600 jth=1200 basis=true"
    assert_contains "$out" "fan0=6700"
    assert_contains "$out" "jth_series=true"
}

test_an_outage_breaks_the_real_time_line_and_no_window_spans_it() {
    # 2026-09-28 18:25-18:36Z the forward was down for 11 min and the chart drew
    # straight across it (#21). A point needs a window no longer than 1.5 x its own.
    local out; out=$(check realtime-gap)
    assert_contains "$out" "break=true spanned=false points=true"
}

test_the_page_can_pull_its_missed_history_from_the_server() {
    # Ronald 2026-09-28: the dashboard lost its state on a tab switch and refilled slowly.
    local out; out=$(check history-feed)
    assert_contains "$out" "hashrate=true fans=true die=true coverage=true"
    assert_contains "$out" "since=true"
}

draw_page() { # -> "rt=<drew> jt=<drew>" or "error=..." from the /live page's own script, stub DOM
    node --input-type=module - "$LV" <<'JS' 2>&1
import fs from 'node:fs'; import vm from 'node:vm';
const src = fs.readFileSync(process.argv[2], 'utf8');
const m = src.match(/const HISTORY_PAGE = `([\s\S]*?)`;\n/);
const page = new Function('return `' + m[1] + '`')();   // the literal as node builds it
const script = page.match(/<script>([\s\S]*?)<\/script>/)[1];
const els = new Map();
const el = (id) => { if (!els.has(id)) els.set(id, { id, innerHTML: '', textContent: '', value: '', style: {}, dataset: {}, setAttribute() {}, addEventListener() {}, querySelectorAll: () => [], appendChild() {}, classList: { add() {}, remove() {}, toggle() {} } }); return els.get(id); };
const document = { getElementById: el, querySelectorAll: () => [], querySelector: () => el('q'), createElement: () => el('new'), addEventListener() {}, visibilityState: 'visible', hidden: false };
const ctx = vm.createContext({ document, window: {}, fetch: () => new Promise(() => {}), setInterval: () => 0, setTimeout: () => 0, clearTimeout() {}, clearInterval() {}, console, location: { search: '', hash: '' }, localStorage: { getItem: () => null, setItem() {} }, addEventListener() {} });
try {
  vm.runInContext(script, ctx);
  const t = Date.now(), p = (dt) => [t - dt, 3e12, 5, [1e12, 1e12, 1e12], 25];
  vm.runInContext(`rt = ${JSON.stringify({ windows: { '1m': [p(120000), p(60000), p(0)] }, mujina: [[t - 120000, 3e12], [t, 3e12]], run_start: t - 120000, lookback_ms: { '1m': 0 }, threads: ['t0', 't1', 't2'] })}; drawRT();`, ctx);
  console.log(`rt=${/<path/.test(el('rt').innerHTML)} jt=${/<path/.test(el('jt').innerHTML)}`);
} catch (e) { console.log(`error=${e.constructor.name}: ${e.message}`); }
JS
}

test_the_real_time_and_j_per_th_charts_draw() {
    # A declaration once sat inside a // comment, so drawRT threw before either chart drew.
    local out; out=$(draw_page)
    assert_eq "rt=true jt=true" "$out"
}
