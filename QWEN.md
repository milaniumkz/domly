# DOMLY — QWEN Context

## Project Overview

**DOMLY** is a premium cleaning service ecosystem built with **Flutter** and **Firebase**, targeting apartment cleaning in residential complexes across Kazakhstan. It consists of three applications sharing a single codebase:

| App | Entrypoint | Audience |
|-----|-----------|----------|
| **DOMLY** | `lib/main_customer.dart` | Customers (заказчики) who order cleaning |
| **Domly Pro** | `lib/main_pro.dart` | Cleaners (уборщицы) who perform cleaning |
| **Domly Admin Web** | `lib/main_admin_web.dart` | Admins managing orders, complaints, and payouts |

## Tech Stack

- **Frontend:** Flutter (SDK >= 3.0.0)
- **Backend:** Firebase (Firestore, Auth, Storage, Messaging, Hosting)
- **Cloud Functions:** Node.js 22 (`functions/index.js`)
- **Payments:** ePay (epayment.kz) via Cloud Functions
- **Maps:** Google Maps (`google_maps_flutter`)
- **Auth:** Firebase Phone Auth with real OTP

## Architecture

### Flutter App Structure

```
lib/
├── main.dart              # Shared entry point
├── main_customer.dart     # Customer app entry
├── main_pro.dart          # Cleaner app entry
├── main_admin_web.dart    # Admin web entry
├── firebase_options.dart  # Firebase configuration
├── screens/
│   ├── admin/             # Admin mobile screens
│   ├── admin_web/         # Admin web screens
│   ├── cleaner/           # Cleaner app screens
│   ├── client/            # Customer app screens
│   └── common/            # Shared screens
├── services/              # Business logic services
│   ├── auth_service.dart
│   ├── firestore_data_service.dart
│   ├── payment_link_service.dart
│   ├── notification_service.dart
│   └── ...
├── app/                   # Shared app configuration
├── theme/                 # App theming
└── ui/                    # Shared UI components
```

### Cloud Functions (`functions/index.js`)

Key callable/scheduled functions:

- **Orders:** `createOrderFromRequest`, `createOrderAndInvoice`, `advanceOrderStatus`, `assignCleaner`
- **Payments:** `createPaymentInvoice`, `syncPaymentStatus`, `confirmPayment`, `epayWebhook`
- **Subscriptions:** `generateSubscriptionSlots`, `subscriptionSlotScheduler`
- **Payouts:** `requestWeeklyPayout`, `weeklyPayoutScheduler` (4% tax withholding)
- **Admin:** `processAdminAction`

### Firebase Project

- **Project ID:** `domly-d0f91`
- **Region:** `us-central1`
- **Config files:** `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`

## Key Business Logic

### Order Lifecycle
```
pending_payment → pending_assignment → assigned → in_progress → completed
                                          ↓
                                      disputed → completed | canceled
                                      ↓
                                   canceled
```

### User Tiers (Customers)
| Tier | Min Spent (KZT) | Discount |
|------|----------------|----------|
| NEWBIE | 0 | 0% |
| CLEANSTER | 100,000 | 5% |
| GURU | 500,000 | 10% |
| GOD | 1,500,000 | 10% |

### Cleaner Statuses
| Status | Priority (RU) |
|--------|--------------|
| NEWBIE | 1 — Новичок |
| RELIABLE | 2 — Надежная |
| EXPERT | 3 — Эксперт |
| LEGEND | 4 — Легенда |

## Environment Variables

### Cloud Functions (`functions/.env`)

| Variable | Purpose |
|----------|---------|
| `EPAY_TOKEN_URL` | ePay OAuth URL |
| `EPAY_INVOICE_URL` | ePay invoice creation |
| `EPAY_PAYOUT_URL` | ePay payout endpoint |
| `EPAY_INVOICE_CLIENT_ID/SECRET` | Invoice API credentials |
| `EPAY_PAYOUT_CLIENT_ID/SECRET` | Payout API credentials |
| `EPAY_SHOP_ID` | Shop identifier |
| `EPAY_TERMINAL_ID` | Payment terminal ID |
| `EPAY_PAYOUT_TERMINAL_ID` | Payout terminal ID |
| `EPAY_WEBHOOK_TOKEN` | Webhook verification |
| `SUBSCRIPTION_WINDOW_DAYS` | Subscription booking window (default: 35) |
| `FREE_CANCELLATION_HOURS` | Free cancellation window (default: 12) |
| `MIN_BOOKING_HOURS` | Minimum advance booking time (default: 24) |

### Flutter Runtime (`--dart-define`)

| Variable | Purpose |
|----------|---------|
| `FIREBASE_API_KEY` | Firebase API key |
| `FIREBASE_MESSAGING_SENDER_ID` | FCM sender ID |
| `FIREBASE_APP_ID_ANDROID/IOS/WEB` | Firebase app IDs per platform |
| `SEED_FIRESTORE_ON_START` | Enable demo data seeding (default: `false`) |

## Commands

### Setup
```bash
flutter pub get
```

### Running Apps
```bash
# Customer app
flutter run --target lib/main_customer.dart --flavor domly

# Cleaner app (Domly Pro)
flutter run --target lib/main_pro.dart --flavor domlyPro

# Admin web (Chrome)
flutter run -d chrome --target lib/main_admin_web.dart
```

### Building
```bash
./scripts/build_android_domly.sh       # Android - Customer
./scripts/build_android_domly_pro.sh   # Android - Cleaner
./scripts/build_ios_domly.sh           # iOS - Customer
./scripts/build_ios_domly_pro.sh       # iOS - Cleaner
./scripts/build_web_domly.sh           # Web - Customer
./scripts/build_web_domly_pro.sh       # Web - Cleaner
./scripts/build_web_admin.sh           # Web - Admin
./scripts/check_web_config_consistency.sh # Validate hosting/build config + release entrypoint consistency
./scripts/verify_release_readiness.sh  # Full release preflight (backend + web)
./scripts/post_deploy_web_smoke.sh     # Quick post-deploy URL/title smoke
```

### Deploy Backend
```bash
./scripts/prepare_backend_deploy.sh    # Backend preflight + functions upload access probe
./scripts/deploy_all.sh                # Deploy rules, indexes, storage, functions
./scripts/deploy_functions.sh          # Deploy signInWithOtp only
./scripts/deploy_web_all.sh            # Build and deploy customer/pro/admin hosting
./scripts/check_web_config_consistency.sh # Validate hosting/build config + release entrypoint consistency
./scripts/verify_release_readiness.sh  # Backend runtime/syntax/access + analyze, test, build, smoke URLs
./scripts/post_deploy_web_smoke.sh     # Check live customer/pro/admin URL/title markers after deploy
firebase deploy --only functions       # Deploy functions only
firebase deploy --only firestore:rules # Deploy Firestore rules only
```

`deploy_web_all.sh` validates customer/pro/admin build titles before hosting deploy.
`post_deploy_web_smoke.sh` validates expected title markers on live customer/pro/admin sites after deploy.
Backend deploy scripts validate the Node major version from `functions/package.json` before install/deploy.
If Homebrew `node@22` is installed, backend scripts auto-switch to it through `scripts/use_functions_node_env.sh`.
Backend deploy scripts also probe `functions:generateUploadUrl` through `scripts/check_functions_deploy_access.sh` before running a real deploy.
Functions dependencies are installed through `scripts/install_functions_dependencies.sh`, preferring `npm ci` when the lockfile is present.

### Seed Data (Development)
```bash
node functions/scripts/seed_firestore.js
```

### Cloud Functions Local Dev
```bash
cd functions && npm run serve   # Start Firebase emulators
```

## Project Scripts

| Script | Purpose |
|--------|---------|
| `scripts/deploy_all.sh` | Deploy rules, indexes, storage, and functions |
| `scripts/deploy_functions.sh` | Deploy signInWithOtp only |
| `scripts/check_web_config_consistency.sh` | Validate release config and entrypoint consistency |
| `scripts/verify_release_readiness.sh` | Full backend+web release readiness check |
| `scripts/post_deploy_web_smoke.sh` | Quick live customer/pro/admin URL and title smoke |
| `scripts/check_functions_node_version.sh` | Validate Node major version for functions |
| `scripts/install_functions_dependencies.sh` | Install functions deps via lockfile-aware flow |
| `scripts/use_functions_node_env.sh` | Auto-select matching Node runtime for functions |
| `scripts/check_functions_deploy_access.sh` | Probe Cloud Functions upload access before deploy |
| `scripts/prepare_backend_deploy.sh` | Backend preflight + upload access probe |
| `scripts/build_android_*.sh` | Build Android APK/AAB |
| `scripts/build_ios_*.sh` | Build iOS IPA |
| `scripts/generate_app_icons.sh` | Generate app icons |

## Key Files

| File | Description |
|------|-------------|
| `pubspec.yaml` | Flutter dependencies and config |
| `firebase.json` | Firebase project configuration |
| `firestore.rules` | Firestore security rules |
| `storage.rules` | Firebase Storage security rules |
| `functions/index.js` | All Cloud Functions (~5700 lines) |
| `functions/.env.example` | Template for environment variables |
| `Техническое задание.docx` | Original technical specification (Russian) |

## Development Notes

- **Production auth:** Uses Firebase Auth only (no WappiService, SessionStore, or demo UIDs)
- **Admin roles:** `admin` / `superAdmin` via Firebase custom claims
- **Free cancellation:** Within `FREE_CANCELLATION_HOURS` (default 12h)
- **Payouts:** Weekly payouts to cleaners with 4% tax withholding
- **Slot reminders:** Sent at 24h and 3h before scheduled cleaning
- **Subscription term:** 1 month, window of 35 days for booking
- **Document:** Техническое задание.docx contains the full Russian-language specification
