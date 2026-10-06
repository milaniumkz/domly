# DOMLY Load Testing

This repo includes a callable load-test runner for scheduling contention and read bursts.

## Prerequisites

- Node.js 22+
- A staging or emulator callable base URL
- A JSON file with Firebase `idToken` values and matching `subscriptionId` values for test users

Example tokens file:

```json
[
  {
    "label": "customer-001",
    "idToken": "eyJhbGciOiJSUzI1NiIs...",
    "subscriptionId": "sub_001"
  },
  {
    "label": "customer-002",
    "idToken": "eyJhbGciOiJSUzI1NiIs...",
    "subscriptionId": "sub_002"
  }
]
```

## 1. Mass schedule reads

```bash
node scripts/load_test_domly.js schedule-read-burst \
  --base-url https://us-central1-domly-d0f91.cloudfunctions.net \
  --tokens-file ./tokens.staging.json \
  --date 2026-05-01 \
  --requests 1000 \
  --concurrency 100
```

Checks:

- p95/p99 latency of `getAvailableSlots`
- behavior under hot-path read pressure
- query/read amplification on cleaner schedules

## 2. Slot contention / race condition

```bash
node scripts/load_test_domly.js slot-contention \
  --base-url https://us-central1-domly-d0f91.cloudfunctions.net \
  --tokens-file ./tokens.staging.json \
  --date 2026-05-01 \
  --time "10:00 - 13:04" \
  --requests 1000 \
  --concurrency 100
```

Checks:

- duplicate booking risk
- race conditions in `bookSchedule`
- expected business rejections vs unexpected `500`/timeout failures

## Output

The runner prints:

- total requests
- success/failure counts
- p50 / p95 / p99 latency
- grouped error buckets
- sample failures

## Recommended usage

- Run against staging or Firebase Emulator Suite, not live customer traffic.
- For a full 1000-user scenario prepare 1000 test users with active subscriptions in the same cluster and date window.
- First run `schedule-read-burst`, then `slot-contention` for the hottest returned slot.
