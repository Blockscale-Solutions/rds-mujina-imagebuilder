#!/usr/bin/env node
// Acceptance check for the Device UI, in a real browser (rdsmujina-env #2).
//
//   node tools/ui-accept/accept.mjs <ui-dir> [mock args...]
//
// Serves <ui-dir> with its own mock (dev/mock-api.mjs), loads /ui/ in headless
// Chromium at desktop and phone widths, and fails when the page lets its /miner
// feed go stale by the UI's own threshold (#78), asks for anything but
// allowlisted GETs, throws, scrolls sideways at 400 px, or renders an
// identifier that must never reach the page. It prints what it
// measured either way, so a pass can be checked and a failure has its evidence.
//
// Env: UI_ACCEPT_HOME (playwright install, default <project>/build/ui-accept),
//      UI_ACCEPT_DWELL_MS (default 8000), UI_ACCEPT_PORT (default 7840),
//      UI_ACCEPT_SHOTS (directory; when set, full-page screenshots are saved).
import { spawn, execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { cadence, staleAfterMs } from './cadence.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const home = process.env.UI_ACCEPT_HOME || path.resolve(here, '../../../../build/ui-accept');
execFileSync(path.join(here, 'setup.sh'), { stdio: 'inherit', env: { ...process.env, UI_ACCEPT_HOME: home } });
const { chromium } = createRequire(import.meta.url)(path.join(home, 'node_modules/playwright-core'));

const [uiDir, ...mockArgs] = process.argv.slice(2);
if (!uiDir) { console.error('usage: accept.mjs <ui-dir> [mock args]'); process.exit(64); }
const DWELL = Number(process.env.UI_ACCEPT_DWELL_MS || 8000);
const PORT = String(process.env.UI_ACCEPT_PORT || 7840);
const SHOTS = process.env.UI_ACCEPT_SHOTS;
const base = `http://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Real identifiers that must never render: tty names from the unit, and any
// host:port that is not the scrubbed placeholder pool.
const MUST_NOT_RENDER = [/tty9bit\d+/i, /\b(?!pool\.invalid)[a-z0-9-]+(\.[a-z0-9-]+)+:\d{2,5}\b/i];
const ALLOW = [/^\/api\/v0\/miner$/, /^\/api\/v0\/health$/, /^\/api\/v0\/boards\/[^/]+\/bzm2\/(asic-summary|chain-summary)$/];

// The UI's own stale threshold, read from the tree under test (#78).
const STALE_MS = staleAfterMs((await import(pathToFileURL(path.resolve(uiDir, 'ui/js/config.js')))).CONFIG);

const mock = spawn('node', ['dev/mock-api.mjs', '--port', PORT, ...mockArgs], { cwd: uiDir, stdio: 'ignore' });
let failures = 0;
const fail = (view, msg) => { failures++; console.log(`FAIL ${view}: ${msg}`); };
try {
  let up = false;
  for (let i = 0; i < 50 && !up; i++) { try { await fetch(`${base}/api/v0/health`, { signal: AbortSignal.timeout(2000) }); up = true; } catch { await sleep(200); } }
  if (!up) { fail('mock', `did not answer on ${base}`); throw new Error('mock down'); }
  const browser = await chromium.launch();
  try {
    for (const v of [{ name: 'desktop-1440', w: 1440, h: 1000 }, { name: 'phone-400', w: 400, h: 900 }]) {
      const ctx = await browser.newContext({ viewport: { width: v.w, height: v.h } });
      const page = await ctx.newPage();
      const reqs = [], errors = [];
      page.on('request', (r) => { const u = new URL(r.url()); if (u.pathname.startsWith('/api/')) reqs.push({ m: r.method(), p: u.pathname, t: Date.now() }); });
      page.on('pageerror', (e) => errors.push(e.message));
      await page.goto(`${base}/ui/`, { waitUntil: 'load' });
      await sleep(DWELL);
      const dwellEnd = Date.now();
      if (SHOTS) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, `${v.name}.png`), fullPage: true }); }
      const text = await page.evaluate(() => document.body.innerText);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      const boards = await fetch(`${base}/api/v0/miner`, { signal: AbortSignal.timeout(5000) }).then((r) => r.json()).then((m) => (m.boards || []).map((b) => b.name)).catch(() => []);
      await ctx.close();

      const byPath = {};
      for (const r of reqs) byPath[r.p] = (byPath[r.p] || 0) + 1;
      console.log(`view ${v.name}: ${reqs.length} API requests in ${DWELL} ms; requests by path: ${JSON.stringify(byPath)}`);
      const c = cadence(reqs.filter((r) => r.p === '/api/v0/miner').map((r) => r.t), dwellEnd, STALE_MS);
      console.log(`view ${v.name}: /miner ${c.polls} polls, median interval ${c.medianMs} ms, largest gap ${c.maxGapMs} ms, stale at ${STALE_MS} ms`);
      for (const f of c.failures) fail(v.name, f);
      for (const b of boards) {
        for (const kind of ['chain-summary', 'asic-summary']) {
          const p = `/api/v0/boards/${encodeURIComponent(b)}/bzm2/${kind}`;
          if (!byPath[p]) fail(v.name, `${kind} never requested for ${b}`);
        }
      }
      for (const r of reqs) {
        if (r.m !== 'GET') fail(v.name, `${r.m} ${r.p}: only GET is allowed`);
        if (!ALLOW.some((re) => re.test(r.p))) fail(v.name, `${r.p} is not on the allowlist`);
      }
      for (const e of errors) fail(v.name, `page threw: ${e}`);
      if (v.w <= 400 && overflow > 0) fail(v.name, `scrolls ${overflow} px sideways`);
      for (const re of MUST_NOT_RENDER) { const m = text.match(re); if (m) fail(v.name, `rendered a real identifier: ${m[0]}`); }
    }
  } finally { await browser.close(); }
} catch (e) {
  if (!failures) fail('harness', e.message);
} finally {
  mock.kill('SIGTERM');
}
console.log(failures ? `FAIL: ${failures} failure(s)` : 'PASS');
process.exit(failures ? 1 : 0);
