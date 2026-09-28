// Is the page's /miner feed live for the whole dwell, by the UI's own measure? (#78)
//
// The UI marks its /miner data stale at liveMultiplier x minerIntervalMs
// (ui/js/config.js). The acceptance check reads that threshold from the tree
// under test, rather than keeping a copy of the interval, and fails on any
// stretch of the dwell without a /miner request that is longer than it.

export function staleAfterMs(config) {
  const { minerIntervalMs: interval, liveMultiplier: k } = config || {};
  if (!(interval > 0) || !(k > 0)) {
    throw new Error(`config needs positive minerIntervalMs and liveMultiplier, got ${interval} and ${k}`);
  }
  return interval * k;
}

// times: ms of each /miner request, ascending; end: ms the dwell ended.
export function cadence(times, end, staleMs) {
  const failures = [];
  const gaps = times.slice(1).map((t, i) => t - times[i]);
  const sorted = [...gaps].sort((a, b) => a - b);
  const medianMs = sorted.length ? sorted[Math.floor(sorted.length / 2)] : null;
  if (times.length < 2) failures.push(`/miner polled ${times.length} time(s); a cadence needs at least 2`);
  gaps.forEach((g, i) => {
    if (g > staleMs) failures.push(`/miner gap of ${g} ms after request ${i + 1} exceeds the UI's stale threshold of ${staleMs} ms`);
  });
  if (times.length && end - times[times.length - 1] > staleMs) {
    failures.push(`no /miner request in the last ${end - times[times.length - 1]} ms of the dwell (stale threshold ${staleMs} ms)`);
  }
  return { polls: times.length, medianMs, maxGapMs: gaps.length ? sorted[sorted.length - 1] : null, failures };
}
