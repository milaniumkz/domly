#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {_: []};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      args._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

function usage() {
  console.log(`
Usage:
  node scripts/load_test_domly.js schedule-read-burst --base-url <callableBase> --tokens-file <json> --date 2026-05-01 [--requests 1000] [--concurrency 50]
  node scripts/load_test_domly.js slot-contention --base-url <callableBase> --tokens-file <json> --date 2026-05-01 --time "10:00 - 13:04" [--requests 1000] [--concurrency 50]
  node scripts/load_test_domly.js offer-accept-contention --base-url <callableBase> --tokens-file <json> --offer-id <offerId> [--requests 100] [--concurrency 20]
`);
}

function loadParticipants(filePath, {requireSubscription = true} = {}) {
  const absolute = path.resolve(filePath);
  const raw = fs.readFileSync(absolute, 'utf8');
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error('tokens-file must be a non-empty JSON array');
  }
  for (const [index, item] of parsed.entries()) {
    if (!item?.idToken || (requireSubscription && !item?.subscriptionId)) {
      throw new Error(
        requireSubscription
          ? `Participant at index ${index} must include idToken and subscriptionId`
          : `Participant at index ${index} must include idToken`
      );
    }
  }
  return parsed;
}

async function callCallable({baseUrl, fnName, idToken, data}) {
  const startedAt = Date.now();
  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/${fnName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({data}),
  });

  let body = null;
  try {
    body = await response.json();
  } catch (_) {
    body = null;
  }

  const latencyMs = Date.now() - startedAt;
  if (!response.ok || body?.error) {
    const error = body?.error || {};
    return {
      ok: false,
      latencyMs,
      code: error.status || error.code || String(response.status),
      message: error.message || response.statusText || 'Unknown error',
    };
  }

  return {ok: true, latencyMs, result: body?.result};
}

async function runWithConcurrency(items, concurrency, worker) {
  const results = [];
  let cursor = 0;

  async function consume() {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await worker(items[index], index);
    }
  }

  await Promise.all(
    Array.from({length: Math.max(1, concurrency)}, () => consume())
  );
  return results;
}

function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)
  );
  return sorted[index];
}

function summarize(results) {
  const latencies = results.map((item) => item.latencyMs).sort((a, b) => a - b);
  const failures = results.filter((item) => !item.ok);
  const errorBuckets = failures.reduce((acc, item) => {
    const key = `${item.code}: ${item.message}`;
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  return {
    total: results.length,
    success: results.length - failures.length,
    failed: failures.length,
    p50Ms: percentile(latencies, 50),
    p95Ms: percentile(latencies, 95),
    p99Ms: percentile(latencies, 99),
    maxMs: latencies[latencies.length - 1] || 0,
    errorBuckets,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const scenario = args._[0];
  if (args.help) {
    usage();
    process.exit(0);
  }
  if (!scenario) {
    usage();
    process.exit(1);
  }

  const baseUrl = String(args['base-url'] || '');
  const tokensFile = String(args['tokens-file'] || '');
  const date = String(args.date || '');
  const time = String(args.time || '');
  const offerId = String(args['offer-id'] || '');
  const requests = Math.max(1, Number(args.requests || 1000));
  const concurrency = Math.max(1, Number(args.concurrency || 50));

  if (!baseUrl || !tokensFile || !date) {
    throw new Error('--base-url, --tokens-file and --date are required');
  }
  if (scenario === 'slot-contention' && !time) {
    throw new Error('--time is required for slot-contention');
  }
  if (scenario === 'offer-accept-contention' && !offerId) {
    throw new Error('--offer-id is required for offer-accept-contention');
  }

  const participants = loadParticipants(tokensFile, {
    requireSubscription: scenario !== 'offer-accept-contention',
  });
  const invocations = Array.from(
    {length: requests},
    (_, index) => participants[index % participants.length]
  );

  console.log(JSON.stringify({
    scenario,
    baseUrl,
    date,
    time: time || null,
    offerId: offerId || null,
    requests,
    concurrency,
    participants: participants.length,
  }, null, 2));

  const results = await runWithConcurrency(invocations, concurrency, async (participant) => {
    if (scenario === 'schedule-read-burst') {
      return callCallable({
        baseUrl,
        fnName: 'getAvailableSlots',
        idToken: participant.idToken,
        data: {subscriptionId: participant.subscriptionId, date},
      });
    }

    if (scenario === 'slot-contention') {
      return callCallable({
        baseUrl,
        fnName: 'bookSchedule',
        idToken: participant.idToken,
        data: {
          subscriptionId: participant.subscriptionId,
          selections: [{date, time}],
        },
      });
    }

    if (scenario === 'offer-accept-contention') {
      return callCallable({
        baseUrl,
        fnName: 'acceptOrderOffer',
        idToken: participant.idToken,
        data: {offerId},
      });
    }

    throw new Error(`Unknown scenario: ${scenario}`);
  });

  const summary = summarize(results);
  console.log(JSON.stringify(summary, null, 2));

  const sampleFailures = results.filter((item) => !item.ok).slice(0, 10);
  if (sampleFailures.length > 0) {
    console.log('\nSample failures:');
    for (const item of sampleFailures) {
      console.log(`- [${item.code}] ${item.message} (${item.latencyMs}ms)`);
    }
  }

  process.exit(summary.failed > 0 ? 2 : 0);
}

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
