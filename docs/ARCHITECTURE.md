# SplitUp: ARCHITECTURE.md

> System design for the SplitUp Android app, backend and website.
> Read with `PRD.md` (what to build), `DESIGN.md` (how it looks), `APP_RULES.md` (balance and settlement logic), `DATABASE.md` (schema) and `API.md` (endpoint contract).
> **Rule for the agent:** follow this structure. If you need to deviate, state the reason and update this file in the same change.

---

## 1. System Overview

```
                        +----------------------+
                        |  Firebase (Google)   |
                        |  Auth (Google/email/ |
                        |  phone OTP) + FCM    |
                        +----------+-----------+
                                   ^  ID token / push
                                   |
+--------------------+   HTTPS     |      +------------------------+      +-----------+
|  Flutter app       |<----------->+----->|  Backend API (Node/TS)  |<---->|  MySQL 8  |
|  (Android APK)     |  REST+JSON         |  Express, Firebase Admin |      |  InnoDB   |
|  Riverpod + drift  |                    +------------------------+      +-----------+
|  (SQLite cache)    |
+---------+----------+
          |  opens device SMS app (invite)         +----------------------------+
          +---------------------------------------->  Website (static): download |
                                                    |  page, APK, privacy policy |
                                                    +----------------------------+
```

**Principles**
1. **The server is the source of truth.** MySQL holds all shared data. The phone holds a cache plus private, device-only data.
2. **Balances are computed, never stored as editable values** (see `PRD.md` 3.3).
3. **One engine, three ledger types.** Individual, group and trip are the same machinery with feature flags.
4. **All money is integer paise** end to end (database, API, app).
5. **Everything that changes more than one row runs in one database transaction.**
6. **No secrets in the app.** Only public Firebase configuration ships in the APK.

---

## 2. Repository Layout (monorepo)

```
splitup/
├─ app/                      # Flutter Android app
├─ backend/                  # Node.js + TypeScript API
├─ website/                  # Static download site
├─ docs/                     # PRD.md, DESIGN.md, ARCHITECTURE.md, APP_RULES.md,
│                            # DATABASE.md, API.md, APP_FLOW.md, TASKS.md, DEPLOYMENT.md,
│                            # AGENT_INSTRUCTIONS.md
├─ shared/
│  └─ test-vectors/          # JSON test cases for split/balance/simplify (used by BOTH app and backend tests)
└─ README.md
```

`shared/test-vectors` is important: the backend and the app both implement split math (the app only for live previews), and both must pass the same JSON cases so they never disagree.

---

## 3. Flutter App Architecture

### 3.1 Approach
**Feature-first folders with clean layering inside each feature.** State management is **Riverpod**. Navigation is **go_router**. Local database is **drift** (SQLite). HTTP is **dio**.

### 3.2 Folder structure

```
app/lib/
├─ main.dart
├─ app.dart                         # MaterialApp.router, theme, providers scope
├─ core/
│  ├─ theme/                        # AppTheme, SplitUpColors (ThemeExtension), typography, tokens
│  ├─ widgets/                      # AppBackground, GlassCard, GlassSheet, GlassBar, MoneyText,
│  │                                # Avatar, buttons, AmountInput, EmptyState, StatusChip
│  ├─ money/                        # formatPaise(), parsing, Paise type helpers
│  ├─ network/                      # dio client, auth interceptor, error mapping, retry
│  ├─ storage/                      # drift database, DAOs, secure storage
│  ├─ routing/                      # go_router config, route names, guards
│  ├─ firebase/                     # auth service, FCM service
│  ├─ contacts/                     # contacts permission + reading (selected only)
│  ├─ names/                        # displayNameFor() (single place for person names)
│  └─ utils/                        # date, validators, logger
├─ features/
│  ├─ auth/                         # welcome, phone entry, OTP, session
│  ├─ home/                         # summary hero + friends list
│  ├─ friends/                      # add friends, contact picker, friend page, nicknames, invite popup
│  ├─ expenses/                     # add/edit expense, split editor, expense detail, activity log, dispute
│  ├─ groups/                       # list, create, group page (Expenses/Dashboard/Settle), settings
│  ├─ trips/                        # list, create, dashboard, budget meter, settle
│  ├─ settlements/                  # settle flow, offsets, pending/confirm/reject/resubmit, graph
│  ├─ notifications/                # feed, inline actions, push handling
│  ├─ profile/                      # profile, edit, appearance, blocked users, logout
│  └─ app_update/                   # version check + "Update available"
└─ l10n/                            # strings (English first; keep all text out of widgets)
```

Each feature contains:

```
feature_x/
├─ presentation/   # screens, widgets, controllers (Riverpod Notifiers)
├─ domain/         # entities (immutable), repository interfaces, pure logic
└─ data/           # repository impls, DTOs/mappers, remote + local data sources
```

**Dependency rule:** `presentation -> domain <- data`. Presentation never imports data classes directly. Domain has no Flutter or network imports.

### 3.3 State management (Riverpod)
- `AsyncNotifier` / `Notifier` per screen or feature for state; `Provider`s for repositories and services.
- Screens read from **repositories that expose streams from the local cache** and refresh from the network in the background (stale-while-revalidate).
- Models are immutable (use `freezed` plus `json_serializable`).
- Errors are modeled as typed failures (`NetworkFailure`, `AuthFailure`, `ValidationFailure`, `ConflictFailure`, `OutdatedFailure`), mapped to friendly messages in one place.

### 3.4 Navigation (go_router)
- A `ShellRoute` hosts the 4-tab bottom nav (Home, Groups, Trips, Profile). Deep screens are routed **outside** the shell so the nav bar hides.
- Route guards: unauthenticated goes to Welcome; authenticated but unverified phone goes to Phone/OTP; otherwise Home.
- Notification taps deep-link to the related friend, group, trip or settlement request.
- Route table is defined once in `core/routing` and mirrors `APP_FLOW.md`.

### 3.5 Networking
- `dio` client with an **auth interceptor**: attaches `Authorization: Bearer <Firebase ID token>`, refreshes the token on 401 once, then retries.
- Base URL and environment flags come from build configuration (`--dart-define`), never hard-coded.
- Idempotency: write requests that create money records send an `Idempotency-Key` header (UUID generated on the device per user action) so a retry after a network drop cannot create a duplicate.
- Consistent error envelope from the server (section 4.6) is mapped to typed failures.

### 3.6 Local storage (drift / SQLite)
Stores:
- **Cache** of friends, ledgers, expenses, settlements, notifications and computed summaries returned by the server.
- **Private data:** nickname overrides (mirrored from the server), appearance setting, contact-name map, drafts of unsent expenses, last-sync timestamps.
- Not stored locally: Firebase tokens (managed by the SDK), secrets.

Cache rules:
- Every cached row stores `server_updated_at`. Refresh replaces changed rows.
- On logout, **wipe the local database**.
- **v1 offline behavior:** read from cache; write actions require connectivity and show "You're offline." Drafts of an in-progress expense are kept locally so nothing is lost. Offline write queue and sync is phase 7 (leave a `pending_operations` table design in `DATABASE.md` but do not build it yet).

### 3.6.1 Client-side logic that is allowed
- **Live split preview** while typing an expense (equal, exact, percent, shares, rounding). Must pass `shared/test-vectors`.
- **Formatting** (money, dates).
- **Never** compute authoritative balances, simplified payment plans or settlement validity on the client. Always display the server's result. (Reason: one authoritative implementation, no drift.)

### 3.7 Settlement graph rendering
- `SettlementGraph` is a `CustomPainter` inside an `InteractiveViewer`, with a gesture layer for node and link hit-testing.
- Input is a plain list of nodes (user id, display name, avatar, net) and links (from, to, amount, pending flag) delivered by the server for the chosen mode (Simplified or Actual).
- Layout is computed in an `Isolate` (`compute`) to keep the UI thread free: circular layout by default, force relaxation with collision avoidance for larger groups.
- A text list is always rendered alongside it (accessibility).

### 3.8 Push notifications (app side)
- On login, request notification permission (Android 13+), fetch the FCM token and register it with `POST /devices`. Re-register on token refresh. Unregister on logout.
- Foreground messages update the notifications badge and cache. Background taps deep-link via `go_router`.
- The push payload carries only a type and ids. The app then fetches full details from the API (never trust or display sensitive data from payloads alone).

### 3.9 Contacts and invites
- Request `READ_CONTACTS` only when the user taps Add friends. Read the device list locally, filter and search locally.
- Only the **selected** contacts (normalized to E.164) are sent to `POST /friends`.
- Invite uses the device SMS app through an `sms:` URL intent with the preset text. The app cannot know whether the message was sent.
- Normalize phone numbers with a library (`libphonenumber` port) using the user's region (default IN).

### 3.10 Auto-update check
- On app start (and at most once per 12 hours), call `GET /app/version`. If `latest_version_code` is higher than the installed code, show an "Update available" banner linking to the website download page. If `min_supported_version_code` is higher than installed, show a blocking "Please update" screen.

---

## 4. Backend Architecture

### 4.1 Stack
Node.js 20+, **TypeScript**, **Express**, **Knex** (SQL query builder and migrations) with `mysql2`, **zod** for validation, **firebase-admin**, **pino** for logging, **vitest** or **jest** for tests. Run behind HTTPS (reverse proxy such as Caddy or Nginx, or the host's built-in TLS).

### 4.2 Folder structure

```
backend/src/
├─ server.ts                 # bootstraps http server
├─ app.ts                    # express app, middleware, routes
├─ config/                   # env parsing (zod), constants
├─ db/
│  ├─ knex.ts                # connection pool
│  ├─ migrations/            # versioned SQL migrations
│  └─ seeds/                 # dev seed data
├─ middleware/
│  ├─ auth.ts                # verifies Firebase ID token, loads user
│  ├─ requestId.ts
│  ├─ rateLimit.ts
│  ├─ validate.ts            # zod request validation
│  ├─ idempotency.ts
│  └─ errorHandler.ts
├─ modules/                  # one folder per domain area
│  ├─ users/
│  ├─ friends/
│  ├─ ledgers/               # individual, group, trip (shared service + type-specific rules)
│  ├─ expenses/
│  ├─ balances/              # net balance engine + simplification (pure functions)
│  ├─ settlements/           # lifecycle, validation, resubmit
│  ├─ offsets/               # atomic group<->individual offsets
│  ├─ notifications/         # feed + FCM sender
│  ├─ devices/
│  ├─ disputes/
│  ├─ activity/              # activity log writer
│  └─ appVersion/
├─ jobs/                     # scheduled tasks (reminders, budget warnings)
├─ lib/                      # money helpers, phone normalization, errors, ids, clock
└─ tests/                    # unit and integration tests
```

Each module has: `routes.ts` (HTTP), `service.ts` (business logic), `repo.ts` (SQL), `schemas.ts` (zod), and tests.

### 4.3 Layering rules
- **Routes** parse and validate input, call a service, and shape the response. No SQL or business rules.
- **Services** hold business rules and orchestrate transactions. They receive a `Tx` (transaction handle) so several repos can participate in one transaction.
- **Repos** contain SQL only.
- **`balances` module is pure**: functions that take lists of expenses, splits, payers and confirmed settlements and return net balances, pairwise debts and the simplified plan. No database access inside the math. This makes it trivially testable against `shared/test-vectors`.

### 4.4 Authentication and authorization
1. App sends `Authorization: Bearer <Firebase ID token>`.
2. `auth` middleware verifies it with `firebase-admin`, extracts `uid` and the verified phone number.
3. It loads the user by `firebase_uid`. If none exists but a **verified phone** is present, it creates the user, or **merges a matching placeholder** (section 5.5).
4. Requests from accounts without a verified phone number are rejected, except the endpoints needed to complete verification.
5. **Authorization:** every ledger-scoped endpoint checks membership of the caller in that ledger (and role for admin-only actions). A user can never read or write a ledger they are not a member of. Centralize this in one `assertMember(ledgerId, userId)` / `assertAdmin(...)` helper.

### 4.5 Money and transaction rules
- Amounts are `BIGINT` paise in the database, `number` (safe integer) in JSON. Reject non-integers and negatives where not allowed.
- **Transactions:** create expense (with payers and splits), create settlement, confirm settlement, create and confirm offset, merge placeholder, delete or edit expense with activity log. Use `READ COMMITTED` or `REPEATABLE READ` consistently and **lock** the rows involved (`SELECT ... FOR UPDATE` on the settlement and on the ledger's members) before re-checking validity.
- **Invariants checked in code and tests:**
  - sum of payer amounts equals expense total
  - sum of split amounts equals expense total (excluded members have 0)
  - sum of all net balances in a ledger equals 0
  - settlement amount is a positive integer within the validity rule from `APP_RULES.md`
- **Idempotency:** `Idempotency-Key` stored with the resulting resource id (table `idempotency_keys`, unique per user and key, expires after 24 hours). A repeated key returns the original result.

### 4.6 API conventions
- REST, JSON, `/v1` prefix. Resource names are plural nouns. IDs are opaque strings (ULID or UUID).
- Timestamps are ISO-8601 in **UTC**. Date-only fields are `YYYY-MM-DD`.
- Pagination: **cursor-based** (`?limit=&cursor=`) for expenses, notifications and activity.
- Error envelope:

```json
{ "error": { "code": "SETTLEMENT_OUTDATED", "message": "Amount is no longer valid", "details": {} } }
```

- Standard codes: `VALIDATION_ERROR`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `SETTLEMENT_OUTDATED`, `UNSETTLED_BALANCE`, `RATE_LIMITED`, `INTERNAL`.
- Full contract in `API.md`.

### 4.7 Notifications service
- Writing a notification = insert into `notifications` (the in-app feed) **and** enqueue an FCM push to the user's registered devices, in that order, after the main transaction commits (never push for something that rolled back).
- Notification rows hold `type`, `payload` (ids and display-safe values), and `action_state` (for inline Confirm/Reject: `OPEN`, `DONE`, `EXPIRED`).
- Push payloads contain only `type` and ids. Remove invalid FCM tokens when FCM reports them as unregistered.
- **Privacy rule:** notification text is rendered for the **recipient**, using the sender's profile name or the recipient's own nickname for the sender. **Never include the sender's private nickname for the recipient.**

### 4.8 Background jobs
Use a lightweight scheduler inside the API process (`node-cron`) for v1, with a design that can move to a separate worker later.
- **Pending settlement reminders** to the receiver (for example after 2 and 5 days), at most once per interval, capped.
- **Budget warnings:** triggered at the time an expense is saved (not by cron): when spent crosses 80% and 100% of budget, notify trip members once per threshold.
- **Cleanup:** expire idempotency keys, purge stale device tokens.

### 4.9 Real-time updates
No websockets in v1. Freshness comes from: FCM push (event hints), refresh on app resume, pull-to-refresh, and refetch after every successful write.

### 4.10 Observability
- Structured logs (pino) with request id, user id, route, latency. **Never log tokens, phone numbers in full, or amounts with names together unnecessarily.**
- Health endpoint `GET /health` (checks database connectivity).
- Error tracking (optional): Sentry on backend and app.

---

## 5. Key Flows (technical sequences)

### 5.1 Add expense
1. App builds the request locally (preview math runs on device) and sends `POST /v1/ledgers/:id/expenses` with `Idempotency-Key`.
2. Backend validates membership, invariants (payers sum, splits sum, "Not there" members get 0 and cannot be payers), and recomputes shares server-side (the server's rounding wins).
3. In one transaction: insert expense, payers, splits, activity log row.
4. After commit: for trips, evaluate budget thresholds and notify. Return the expense and updated ledger summary.
5. App updates its cache and UI.

### 5.2 Create settlement (sender)
1. Sender taps **Settle (amount)** on a row where they pay. App calls `POST /v1/settlements` (`ledger_id`, `to_user_id`, `amount_paise`, `method`).
2. Backend verifies the sender is a member and is the **payer**, the amount passes the validity rule (`APP_RULES.md`), and creates `PENDING` plus an event row.
3. If the receiver is a **placeholder** (not on the app): the creator of that placeholder confirms on their behalf: the settlement is created with `confirmed_on_behalf = true` and **self-confirmed (unverified)** labeling. (If the sender *is* that creator, it confirms immediately with that flag. Otherwise the creator receives the confirmation request.)
4. Otherwise, notify the receiver (feed plus push) with inline Confirm/Reject.

### 5.3 Confirm or reject (receiver)
1. Receiver opens the request: `GET /v1/settlements/:id` runs the **validity re-check** (option a). If invalid, status becomes `OUTDATED`, the sender is notified, and the response says so.
2. On `POST /v1/settlements/:id/confirm`: begin transaction, lock the settlement row and ledger member rows, **re-validate again**, set `CONFIRMED`, write event, update notification `action_state`, commit.
3. `POST /v1/settlements/:id/reject` sets `REJECTED` (no reason field).
4. Only the receiver (or the creator acting for a placeholder) can confirm or reject. Only the sender can cancel while `PENDING`.

### 5.4 Resubmit
`POST /v1/settlements/:id/resubmit` (sender only, status `REJECTED` or `OUTDATED`): reads the current valid amount; if none, returns `NOTHING_DUE`; otherwise creates a **new** `PENDING` settlement, links `replaced_by` on the old one, and notifies the receiver. Notification is suppressed if the same amount was rejected within the last 24 hours (see `PRD.md` 4.10).

### 5.5 Placeholder merge
Triggered in the `auth` middleware or `POST /auth/verify-phone` when a new user verifies phone number P and a placeholder with P exists:
1. In one transaction: re-point all references (`ledger_members`, `expense_payers`, `expense_splits`, `settlements`, `friendships`, `notifications`, `activity_log`) from the placeholder user id to the real user id, resolving duplicate memberships safely.
2. Delete the placeholder row.
3. Notify the placeholder's creator(s): "Rahul joined."
4. Return a merge summary so the app can show the first-launch explainer (count and total of expenses).

### 5.6 Offset (group with individual)
1. `POST /v1/offsets` with `group_ledger_id`, `to_user_id`, `amount_paise`.
2. Backend computes `min(group amount owed, individual amount available)` and creates **one offset record** with two linked pending settlement entries (group and individual), in one transaction.
3. The receiver sees one request. `confirm` re-validates **both** balances under locks; if either changed the whole offset becomes `OUTDATED`. On success both entries become `CONFIRMED` in the same transaction. `reject` rejects both.

### 5.7 Add friend
1. App sends the selected contact's name and normalized number to `POST /v1/friends`.
2. Backend finds a user by phone. If **exists**: create a bidirectional friendship (and the individual ledger) and send an in-app notification (plus push) to them with Remove/Block actions. If **not**: create a placeholder user (`created_by` = caller), the friendship and the individual ledger, and return `is_app_user: false` so the app shows the Invite via SMS popup.
3. If the friendship exists already, return it with `already_friends: true`.
4. Blocked users are rejected silently from the blocker's side (the blocker's friend list stays clean; no notification is sent).

### 5.8 Contact lookup privacy
`POST /v1/contacts/lookup` accepts only numbers the user explicitly selected, rate limited (for example 60 numbers per hour), returns `{ phone, is_user, name?, photo? }` only.

---

## 6. Data Flow and Caching Summary

| Data | Source of truth | Cached on device | Notes |
|---|---|---|---|
| Users (profile), friends, ledgers | MySQL | Yes | Refresh on resume |
| Expenses, settlements | MySQL | Yes | Writes online only in v1 |
| Net balances, graph data, simplified plan | Computed by server | Yes (display only) | Never recomputed on client |
| Budget meter inputs | Server (budget, spent) | Yes | Meter drawn locally from server numbers |
| Nicknames | MySQL `friendships` (per viewer) | Yes | Never sent to other users |
| Contact names | Device contacts | Yes (map) | Priority: nickname, contact, profile name |
| Appearance mode, drafts | Device only | Yes | Not on server |
| Notifications | MySQL | Yes | Plus FCM hints |

---

## 7. Security Architecture

- TLS everywhere. HSTS on the website and API.
- Firebase token verification on every request, short-lived tokens.
- Authorization by ledger membership, tested explicitly (negative tests for non-members).
- Input validation with zod on every endpoint; parameterized queries only (Knex bindings), no string-built SQL.
- Rate limits: auth, contact lookup, settlement creation, notification-producing actions (per user and per IP).
- Secrets via environment variables / host secret store. The Firebase service account key lives only on the server, is never committed, and never ships in the app. `.env` is git-ignored; provide `.env.example`.
- Android: release build with R8 shrinking; no logging of sensitive values in release; `allowBackup` disabled or restricted so the local database is not extracted by backup.
- Deleted accounts: personal fields wiped, rows retained as "Deleted user" so others' balances stay correct.
- Dependency hygiene: pin versions, enable automated audit (`npm audit`, `flutter pub outdated`).

---

## 8. Environments and Configuration

| Environment | Backend | Database | Firebase project |
|---|---|---|---|
| `dev` | Local (docker-compose with MySQL) | Local MySQL | Dev project with test phone numbers |
| `prod` | Hosted server | Managed or self-managed MySQL with daily backups | Prod project |

- App configuration via `--dart-define` (`API_BASE_URL`, `ENV`). Two Firebase config sets, selected by build flavor (`dev`, `prod`).
- Backend configuration via environment variables validated at startup (the server refuses to start if required variables are missing).
- Database changes only through migrations. Never edit the production schema by hand.

---

## 9. Testing Strategy

| Level | What | Tools |
|---|---|---|
| Unit (backend) | Split math, rounding, net balances, simplification, settlement validity, offset math, phone normalization | vitest/jest, **shared test vectors** |
| Integration (backend) | Each endpoint against a real MySQL (docker): auth, membership checks, transactions, idempotency, placeholder merge, outdated detection | supertest |
| Property tests | Zero-sum invariant, shares sum to total, simplification clears all balances | fast-check |
| Unit (app) | Split preview, `formatPaise`, `displayNameFor`, mappers | flutter_test |
| Widget (app) | Money text, Settle button visibility rule, budget meter levels, empty states | flutter_test, golden tests for key components in light and dark |
| Integration (app) | Core flows with a mocked API | integration_test |
| Manual release checklist | Release APK on 2 to 3 real phones: Google sign-in, phone OTP, push, contacts, SMS invite, update check | `DEPLOYMENT.md` |

**Must-have tests** (from `PRD.md` section 12): basic dinner split, rounding to the paisa, "Not there," simplification at most n-1 payments, settlement confirm/reject/outdated/resubmit, offset atomicity, trip isolation, nickname privacy, placeholder merge, budget meter levels, Settle button only on rows where the user pays.

---

## 9.1 CI (suggested)
On every push: backend lint, typecheck, unit and integration tests (MySQL service container); app `flutter analyze` and tests. On tags: build the release APK and attach it to a release.

---

## 10. Deployment Topology (v1)

- **Backend:** one container or process behind a reverse proxy with HTTPS. Horizontal scaling is not needed at friends scale, but keep the API **stateless** (no in-memory session state; the scheduler tolerates a single instance).
- **MySQL:** managed instance or a VM with automated daily backups and a tested restore procedure.
- **Website:** static hosting (Cloudflare Pages, Netlify, Vercel, or the same server). The APK file is served over HTTPS with the correct content type, ideally from object storage or releases hosting.
- Details in `DEPLOYMENT.md`.

---

## 11. Key Architecture Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | Server-authoritative balances; client never computes them | One implementation, no drift, easy to test |
| 2 | Pure `balances` module, shared test vectors | Money correctness is the product |
| 3 | Integer paise everywhere | No floating-point errors |
| 4 | Riverpod + feature-first + clean layers | Testable, scales as features grow |
| 5 | drift (SQLite) as a read cache in v1; offline writes deferred | Delivers speed now, avoids the hardest sync problem early |
| 6 | Firebase for auth and push only; data in MySQL | Relational data and atomic offsets suit SQL |
| 7 | Knex over a heavy ORM | Explicit SQL and row locking for money transactions |
| 8 | Idempotency keys on money-creating writes | Safe retries on bad networks |
| 9 | Push as a hint, API as truth | Avoids stale or leaked data in payloads |
| 10 | Placeholder users merged by verified phone | Lets friends be added before they join |
| 11 | SMS invite via the device SMS app | No server SMS cost or DLT registration |
| 12 | Trips fully isolated; offsets only group <-> individual | Matches product rules, simpler consistency |
| 13 | No websockets in v1 | Push plus refetch is enough for the scale |

---

## 12. Code Conventions

**Dart / Flutter**
- Lint with `flutter_lints` (strict). Files `snake_case.dart`, classes `PascalCase`.
- No business rules in widgets. No colors, sizes or fonts hard-coded in screens (see `DESIGN.md`).
- Every user-visible string goes through `l10n`.
- Money is typed: use `int paise` and `MoneyText` / `formatPaise`; never `double`.

**TypeScript / Node**
- `strict` mode on. ESLint plus Prettier. Files `camelCase.ts` or `kebab-case.ts` consistently within the project.
- No `any` in services. Validate all external input with zod.
- SQL column names `snake_case`, JSON field names `snake_case` (match `API.md` exactly).
- One migration per schema change, never edited after being applied.

**Git**
- Small, focused commits. Branch per phase or feature. Never commit secrets, keystores or `.env`.

---

## 13. Out of Scope for This Architecture (v1)

Offline write queue and sync, websockets, iOS, multi-currency, in-app payments, receipt OCR, push via anything other than FCM, microservices. Design choices above leave room to add each later without rewrites.