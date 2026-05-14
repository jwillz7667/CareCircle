<div align="center">

# CareCircle

**Family-caregiving coordination, built for everyone keeping someone safe at home.**

iOS app + cloud backend that unifies medication schedules, vitals, SOS alerts, voice handoffs, AI-composed care briefs, live location, and a shared family wall — all under a single Circle owned by the family, not the platform.

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](#)
[![Backend](https://img.shields.io/badge/backend-Node%2022%20%2B%20Fastify%205-339933.svg)](#)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)

</div>

---

## Table of contents

- [Overview](#overview)
- [Feature matrix](#feature-matrix)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Build, lint, test](#build-lint-test)
- [Environment](#environment)
- [Release process](#release-process)
- [Security](#security)
- [Documentation](#documentation)
- [Support](#support)
- [License](#license)

---

## Overview

CareCircle is a multi-caregiver coordination platform for families managing the care of an older adult, a recovering family member, or anyone whose day-to-day wellbeing depends on a trusted circle of people.

The core unit is a **Circle**: one Care Recipient, one Primary Caregiver, and any number of Family Members, Paid Aides, or View-Only viewers. Everyone in a Circle sees the same shared truth — medication schedules, vitals, today's plan, an activity wall, the recipient's last-known location — and every action (a dose taken, a comment posted, an SOS triggered) propagates to every member within seconds.

The product is positioned as a **record-keeping and coordination tool, not a medical device**. Medication-adjacent surfaces carry an explicit "Not medical advice — consult your healthcare provider" footer. The Care Recipient never pays; their data is exportable and deletable on demand.

---

## Feature matrix

| Capability | Where it lives | Status |
|---|---|---|
| Sign in with Apple (iOS + backend) | `Features/Auth`, `backend/apps/api` | Shipped |
| Multi-Circle SwiftData + CloudKit shared zones | `Models/`, `Services/CloudKit` | Shipped |
| Backend-of-record on Railway (Postgres 16 + Redis + MinIO) | `backend/` | Shipped |
| Medication scheduling + dose tracking + NDC pill identifier | `Features/Meds` | Shipped |
| Today timeline + activity feed + comments + reactions | `Features/Today`, `Features/Activity` | Shipped |
| Appointments + documents + emergency contacts | `Features/Appointments`, `Features/Documents` | Shipped |
| SOS + Critical Alert escalation pipeline | `Features/SOS` | Shipped (Critical Alert entitlement pending Apple approval) |
| Care minutes + end-of-shift voice digest | `Features/CareMinutes`, `Features/Shifts` | Shipped |
| Smart insights engine (dose-timing drift, missed-dose risk) | `Features/Insights` | Shipped |
| HealthKit vitals — manual entry + Apple Watch ingestion | `Features/Vitals` | Shipped |
| **Pulse dashboard** — realtime vitals + wellness composite | `Features/Pulse` | Shipped |
| **Bedside Monitor** — ambient ECG + idle-disabled full-screen mode | `Features/Pulse/BedsideMonitorView` | Shipped |
| **AI Care Co-pilot** — on-device brief + voice answers | `Features/Pulse/CareCopilotView` | Shipped |
| **Find** — live Circle location map | `Features/Location` | Shipped |
| **Wall** — Circle-wide chat / shared feed | `Features/Chat` | Shipped |
| Simplified mode (large type, single-action UI) | `Features/SimplifiedMode` | Shipped |
| iOS 26 Foundation Models swap-in for the Co-pilot | — | Planned |

---

## Architecture

Two-tier sync model.

### CloudKit (in-app sharing)

Each Circle is backed by a `CKShare` in the owner's private database. Other members access via `CKContainer.default().sharedCloudDatabase`. A per-circle `CKRecordZone` keyed on the Circle UUID enables clean full-deletion. Sensitive document data is encrypted client-side with `CryptoKit` (AES-256-GCM) before write — the per-circle symmetric key lives in iCloud Keychain and propagates to members through the CKShare invitation flow.

### Railway backend (backend-of-record)

PostgreSQL 16 with FORCE RLS on every PHI table, `pgcrypto` envelope encryption (master key wraps per-circle DEKs), append-only audit log, `LISTEN/NOTIFY` → WebSocket fanout. Fastify 5 API + BullMQ worker + Redis. MinIO for object storage — E2EE for documents, server-side encryption for photos and voice. Sign in with Apple JWT verification, 15-minute access tokens with 30-day refresh rotation.

The iOS app currently writes through CloudKit only. The Railway backend is fully built and tested (68/68 integration tests green); the iOS `APIClient` + `SyncEngine` migration to dual-write is a future task. New iOS features keep working through SwiftData + CloudKit until that migration lands.

### Data flow at a glance

```
                ┌────────────────────────────────────────────┐
                │                  Family                    │
                │  Primary Caregiver · Family · Paid Aide    │
                └────────────────────┬───────────────────────┘
                                     │  Sign in with Apple
                                     ▼
       ┌──────────────────────────────────────────────────────┐
       │                    iOS app (SwiftUI)                 │
       │                                                      │
       │   SwiftData ◄──► CloudKit (private + shared zones)   │
       │       │                                              │
       │       └──► APIClient ◄──► WebSocket realtime         │
       └────────────────────────┬─────────────────────────────┘
                                │ HTTPS / WSS
                                ▼
       ┌──────────────────────────────────────────────────────┐
       │                  Railway backend                     │
       │                                                      │
       │   Fastify 5 API  ──►  Postgres 16 (RLS + pgcrypto)   │
       │        │            └─►  LISTEN/NOTIFY → WS fanout   │
       │        ├──► Redis (cache + BullMQ)                   │
       │        └──► MinIO (E2EE docs · SSE photos/voice)     │
       └──────────────────────────────────────────────────────┘
```

---

## Repository layout

```
CareCircle/
├── CareCircle.xcodeproj/         Xcode project (synchronized root group)
├── CareCircle/                   iOS app target sources
│   ├── Info.plist                Managed via Xcode Info tab (build-settings exception)
│   ├── CareCircle.entitlements   Sign in with Apple + CloudKit + APNs
│   ├── Assets.xcassets/
│   └── Sources/
│       ├── App/                  @main entry, root + tab views, scene wiring
│       ├── Features/             One folder per feature (UI + view-model)
│       │   ├── Auth/             Sign in with Apple flow
│       │   ├── Home/             Multi-circle dashboard
│       │   ├── Today/            Daily timeline of meds + appointments
│       │   ├── Meds/             Schedules, dose events, pill identifier
│       │   ├── Pulse/            Realtime vitals dashboard + bedside + co-pilot
│       │   ├── Vitals/           Manual entry + HealthKit reader
│       │   ├── Location/         Live Find map
│       │   ├── Chat/             Circle wall
│       │   ├── Activity/         Feed posts, reactions, comments
│       │   ├── Appointments/     Calendar items + reminders
│       │   ├── Documents/        E2EE storage of insurance, advance directives, etc.
│       │   ├── SOS/              Emergency event + Critical Alert pipeline
│       │   ├── EmergencyContacts/
│       │   ├── CareMinutes/      Time tracking for paid caregivers
│       │   ├── Shifts/           End-of-shift voice digests
│       │   ├── Insights/         Smart insights engine
│       │   ├── Members/          Circle membership management
│       │   ├── Circle/           Circle creation + sharing
│       │   ├── SimplifiedMode/   Accessibility-first single-action mode
│       │   └── More/             Settings, profile, deep-link entry points
│       ├── Services/             Cross-feature services (sync, auth, push, HK, location, AI)
│       ├── Models/               SwiftData @Model types
│       ├── DesignSystem/         Theme, colors, reusable views
│       └── Core/                 Extensions + utilities used by ≥3 features
├── CareCircleTests/              Future Unit Testing Bundle target root
│   ├── Unit/
│   └── Integration/
├── backend/                      Node 22 + Fastify 5 + Postgres on Railway
│   ├── apps/
│   │   ├── api/                  HTTP + WebSocket
│   │   └── worker/               BullMQ workers
│   ├── packages/
│   │   ├── shared/               Zod schemas + types shared between API and worker
│   │   └── db/                   Prisma client + migrations
│   ├── docker-compose.yml        Local Postgres + Redis + MinIO
│   ├── Dockerfile
│   ├── pnpm-workspace.yaml
│   └── package.json
├── docs/                         Spec, build prompt, phase plans, ADRs
│   ├── CARECIRCLE_SPEC.md
│   ├── CARECIRCLE_BUILD_PROMPT.md
│   ├── CARECIRCLE_DATABASE_SPEC.md
│   ├── CRITICAL_ALERTS_APPLICATION.md
│   └── phases/                   PHASE_*_PLAN.md per phase
├── spec-docs/                    Draft / working specs (not authoritative)
├── CLAUDE.md                     Project rules for AI-assisted contributors
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── SECURITY.md
├── NOTICE
├── LICENSE                       Proprietary — see file
├── .editorconfig
├── .gitattributes
├── .gitignore
├── .swiftformat
└── .swiftlint.yml
```

---

## Getting started

### Prerequisites

| Tool | Version |
|---|---|
| macOS | Sonoma 14 or later (Xcode 26 requirement) |
| Xcode | 26.x |
| iOS target | iOS 17.0+ |
| Apple Developer account | Required for CloudKit + Sign in with Apple on a device |
| Node | 22.x (for backend work) |
| pnpm | 9.x |
| Docker | 24.x (local Postgres + Redis + MinIO for backend) |

### Clone

```bash
git clone https://github.com/jwillz7667/CareCircle.git
cd CareCircle
```

### iOS

Open `CareCircle.xcodeproj` in Xcode 26. The project uses a `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file you drop under `CareCircle/` is automatically added to the app target — you do not need to touch `project.pbxproj`.

Select the **CareCircle** scheme + an iOS 17+ simulator, then ⌘R.

> [!IMPORTANT]
> HealthKit reads return empty on the simulator. For end-to-end HK testing you need a physical device signed into iCloud.

### Backend

```bash
cd backend
pnpm install
cp apps/api/.env.example apps/api/.env   # then fill in values
docker compose up -d                     # Postgres + Redis + MinIO
pnpm --filter @carecircle/db migrate
pnpm --filter @carecircle/api dev
```

The API listens on `http://localhost:3000` by default. WebSocket realtime is on the same origin at `wss://.../v1/circles/:id/stream`.

---

## Build, lint, test

### iOS

```bash
# Build for simulator (any installed iPhone simulator)
xcodebuild -project CareCircle.xcodeproj -scheme CareCircle \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build

# List available simulators
xcrun simctl list devices available

# Lint + format checks
swiftlint --strict
swiftformat --lint .
```

A unit test target does not yet exist. When it lands, the test bundle's synchronized root will be the top-level `CareCircleTests/` folder — outside the app's synchronized root so test files never accidentally join the app target.

### Backend

```bash
cd backend
pnpm run lint                    # eslint + biome
pnpm run test                    # vitest unit + integration
pnpm run test:integration        # testcontainers — full DB + Redis
pnpm run typecheck
```

---

## Environment

Every secret is read from environment variables. Nothing is committed; `.env*` files are git-ignored.

### iOS

The app reads `BackendConfiguration` from the bundle's `Info.plist` — populate `BACKEND_BASE_URL` and `APPLE_AUTH_CLIENT_ID` via Build Settings (User-Defined) or per-configuration `.xcconfig` files. The Sign in with Apple client ID **must match** the backend's `APPLE_CLIENT_ID`.

### Backend

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Postgres 16 DSN |
| `REDIS_URL` | yes | Redis 7+ |
| `MINIO_ENDPOINT` | yes | S3-compatible object storage |
| `MINIO_ACCESS_KEY` | yes | |
| `MINIO_SECRET_KEY` | yes | |
| `APPLE_CLIENT_ID` | yes | Must match the iOS bundle ID used for SIWA |
| `APPLE_KEY_ID` | yes | Apple Developer ▸ Keys |
| `APPLE_TEAM_ID` | yes | Apple Developer ▸ Membership |
| `APPLE_PRIVATE_KEY` | yes | Contents of `AuthKey_*.p8`, base64 |
| `JWT_SECRET` | yes | 32+ random bytes |
| `MASTER_ENCRYPTION_KEY` | yes | base64, 32 bytes — wraps per-circle DEKs |
| `LOG_LEVEL` | no | `info` / `debug` / `warn` |
| `RAILWAY_ENVIRONMENT` | no | populated automatically on Railway |

Run `pnpm --filter @carecircle/api env:check` to validate env presence before boot.

---

## Release process

1. Branch from `main`: `feat/<slug>` or `fix/<ticket>-<slug>`.
2. One logical change per commit. Conventional Commits enforced (`feat:`, `fix:`, `refactor:`, `perf:`, `test:`, `docs:`, `chore:`, `build:`, `ci:`).
3. Open a PR with a written test plan. CI runs swiftlint, swiftformat-lint, `xcodebuild build`, backend lint, backend typecheck, and the backend test suite.
4. Reviewer + green CI required to merge. Squash-merge only.
5. iOS: TestFlight builds are cut from `main` via Xcode Cloud. App Store releases require a tagged release `v<MAJOR>.<MINOR>.<PATCH>`.
6. Backend: pushes to `main` deploy to Railway through GitHub Actions; Railway runs `pnpm --filter @carecircle/db migrate:deploy` automatically as part of the release pipeline.

---

## Security

If you discover a vulnerability, **do not file a public GitHub issue**. Follow the disclosure process described in [SECURITY.md](SECURITY.md). We acknowledge reports within two business days.

CareCircle handles health-adjacent data. The product is positioned as a record-keeping tool, not a medical device, and is not marketed as HIPAA-compliant. Encryption is implemented at multiple layers: TLS in transit, AES-256-GCM at rest for E2EE documents (client-side keying), envelope encryption (`pgcrypto`) for PHI columns at the backend, and per-circle data isolation enforced by Postgres FORCE RLS.

---

## Documentation

Authoritative spec lives under `docs/`:

- [`docs/CARECIRCLE_SPEC.md`](docs/CARECIRCLE_SPEC.md) — product spec
- [`docs/CARECIRCLE_BUILD_PROMPT.md`](docs/CARECIRCLE_BUILD_PROMPT.md) — phased build plan
- [`docs/CARECIRCLE_DATABASE_SPEC.md`](docs/CARECIRCLE_DATABASE_SPEC.md) — backend schema, RLS policy, encryption envelope
- [`docs/CRITICAL_ALERTS_APPLICATION.md`](docs/CRITICAL_ALERTS_APPLICATION.md) — Apple Critical Alert entitlement application
- [`docs/phases/`](docs/phases/) — per-phase plan + acceptance notes
- [`CLAUDE.md`](CLAUDE.md) — project rules and Xcode/SwiftData gotchas, loaded by AI-assisted tooling

---

## Support

| Channel | Use case |
|---|---|
| Email — `support@viral-ventures-llc.com` | General questions, partnership inquiries |
| Email — `security@viral-ventures-llc.com` | Coordinated security disclosure |
| Website — [viral-ventures-llc.com](https://viral-ventures-llc.com) | Company information |

For B2B / enterprise inquiries (assisted-living facilities, home-care agencies), contact `partnerships@viral-ventures-llc.com`.

---

## License

CareCircle is proprietary software.

Copyright © 2026 **Viral Venture LLC**, Maple Grove, Minnesota, USA. All rights reserved.

Use, reproduction, modification, distribution, sublicensing, or any other exploitation of this software or its source code is prohibited without a separate written agreement signed by an authorized officer of Viral Venture LLC. See [LICENSE](LICENSE) for the full text and [NOTICE](NOTICE) for required attribution.
