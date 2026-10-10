# SplitUp: PHASES.md

> Phased build plan for the SplitUp Android app, backend and website.
> Read with `PRD.md` (requirements and requirement IDs), `ARCHITECTURE.md` (structure), `DESIGN.md` (visuals), `APP_FLOW.md` (navigation), `APP_RULES.md` (money logic), `DATABASE.md` and `API.md`.
> Phase numbers match `PRD.md` section 11. Requirement IDs in brackets (for example `FR-4`, `GRP-8`) point to `PRD.md`.

---

## How to Use This File

### Working rules for the agent (every phase)
1. **Plan first.** At the start of a phase, read the listed docs and present a short plan (files to create, order, risks). Wait for approval before writing code.
2. **Build in small steps** inside the phase, following the task order. Do not start the next phase's work early.
3. **Mock first, then connect.** Screens are built with mock data before they are wired to the backend, unless the phase says otherwise.
4. **Tests are part of the work.** A task is not done until its tests pass. Money logic must pass `shared/test-vectors`.
5. **Stop at the end of each phase** with: what was built, what was tested, what is known to be incomplete, and the exit-criteria checklist ticked or not.
6. **Never** hard-code colors/fonts (see `DESIGN.md`), compute balances on the client, use floating point for money, or commit secrets.
7. If a doc is ambiguous or two docs conflict, **ask**, do not guess. `PRD.md` wins for behavior, `DESIGN.md` for visuals.

### Definition of Done (applies to every task)
- Code compiles with no analyzer or lint errors.
- Unit and integration tests for the task exist and pass.
- Works in both light and dark theme (app tasks).
- Loading, empty and error states exist (app tasks).
- Documented in the relevant doc if behavior or structure changed.
- No secrets, keystores or `.env` files in the repository.

### Task size legend
**S** = small (hours) · **M** = medium (about a day) · **L** = large (several days)

### Your own actions (marked 👤 USER)
Some steps cannot be done by the agent: creating accounts, console settings, secrets and real-device testing. They are listed in each phase so nothing blocks you.

---

## Phase Overview

| Phase | Name | Outcome you can see | Size |
|---|---|---|---|
| 0 | Foundations | App shell with theme, shared widgets, navigation and mock data | M-L |
| 1 | Backend core | API and database with the correct balance engine, fully tested | L |
| 2 | Identity and friends | Real sign-in, OTP, profile, friends, SMS invites, nicknames | L |
| 3 | Individual ledger | Expenses and confirmed settlements between two friends, notifications and push | L |
| 4 | Groups | Groups, "Not there", dashboard, graph, simplification, offsets | L |
| 5 | Trips | Trips, budget meter and slider, dashboard, graph, completed state | M-L |
| 6 | Polish and release | Empty and error states, update check, performance pass, release APK and website | M-L |
| 7 | Later | Offline editing and sync, UPI links, receipts, PDF export, iOS, Play Store | Future |

**Dependencies:** 0 and 1 can run in parallel. 2 needs 1 and 0. 3 needs 2. 4 needs 3. 5 needs 4 (reuses ledger, graph, settlement). 6 needs 5. A friends-only test release is possible after Phase 3 (see checkpoints).

---

## Phase 0: Foundations (app shell, no backend)

**Goal:** A runnable Flutter app that looks like SplitUp, navigates between all main screens with mock data, and has every shared building block ready.

**Read first:** `DESIGN.md`, `APP_FLOW.md`, `ARCHITECTURE.md` section 3.

**👤 USER**
- Install Flutter and Android toolchain; confirm `flutter doctor` is clean.
- Connect the Stitch MCP in Antigravity and keep the Stitch project accessible (see earlier setup steps). Place `DESIGN.md` and `APP_FLOW.md` in `docs/`.

**Tasks**
1. **(S)** Create the monorepo structure and the Flutter project with package name `com.splitup.app`. Configure flavors `dev` and `prod`, `--dart-define` config, `flutter_lints`.
2. **(M)** Theme: `AppTheme.dark()` and `AppTheme.light()`, `SplitUpColors` ThemeExtension, typography with Manrope and IBM Plex Mono (bundled), tokens from `DESIGN.md`. Theme mode: light, dark, system.
3. **(M)** Shared widgets: `AppBackground`, `GlassCard`, `GlassSheet`, `GlassBar` (with `reducedEffects` mode), `MoneyText`, `formatPaise` (Indian grouping), `Avatar`, `PrimaryButton`, `SecondaryButton`, `SettleButton`, `AmountInput` with keypad, `EmptyState`, `StatusChip`, `SegmentedControl`.
4. **(M)** Navigation: `go_router` with the 4-tab shell (Home, Groups, Trips, Profile) and routes for every screen in `APP_FLOW.md`. Bottom bar hidden on deep screens. Bell icon with badge on Home, Groups, Trips.
5. **(M)** Mock data layer behind repository interfaces (friends, groups, trips, expenses, settlements, notifications) with realistic Indian names and rupee amounts.
6. **(L)** Build all main screens against mock data, matching the Stitch designs: welcome, phone, OTP, home, friend page, add expense sheet, groups list, create group, group page (3 tabs), trips list, create trip, trip dashboard, settlement screens, notifications, profile and edit profile. Graph screen with a first `CustomPainter` version using mock nodes and links.
7. **(S)** `displayNameFor()` implemented with the nickname, contact name, profile name priority (local only for now).
8. **(S)** Widget and golden tests for the shared widgets in light and dark.

**Exit criteria**
- [ ] App runs on a real Android phone, both themes, no overflow errors.
- [ ] Every screen in `APP_FLOW.md` is reachable by tapping, with mock data.
- [ ] Settle button appears only on rows where the mock user pays.
- [ ] Glass screens hold smooth scrolling on a mid-range phone (note the device used).
- [ ] `formatPaise` has tests (for example 12000000 paise displays as `1,20,000`).

---

## Phase 1: Backend core (balance engine first)

**Goal:** A deployed-ready API and MySQL schema whose **money logic is provably correct**. This is the heart of the product, so no UI work is mixed in.

**Read first:** `APP_RULES.md`, `DATABASE.md`, `API.md`, `ARCHITECTURE.md` section 4.

**⚠ Blocker to resolve before this phase:** `APP_RULES.md` must define the **settlement validity rule** (whether a pending settlement is checked against the direct pairwise debt, the simplified plan or the payer's net balance). Do not start settlement validation until it is written.

**👤 USER**
- Install Docker (for local MySQL) and Node.js 20+.
- Choose where the production backend and MySQL will run (cloud service or VPS). A decision is needed before Phase 6, not now.

**Tasks**
1. **(S)** Backend scaffolding: TypeScript, Express, Knex, config validation (zod), pino logging, `/health`, docker-compose with MySQL.
2. **(M)** Migrations for all tables in `DATABASE.md` (users, friendships, ledgers, ledger_members, expenses, expense_payers, expense_splits, settlements, settlement_events, activity_log, notifications, disputes, device_tokens, idempotency_keys). Foreign keys, indexes, `BIGINT` paise columns.
3. **(L)** `balances` module as **pure functions**: split calculators (equal, exact, percent, shares) with deterministic rounding; net balances per ledger; direct pairwise debts; simplified plan (at most n-1 payments); excluded ("Not there") participants.
4. **(M)** `shared/test-vectors`: JSON cases covering the dinner example (A 200, B 600, C 400 on Rs 1,200), rounding, multiple payers, exclusions, percentages, shares, simplification. Backend tests run them.
5. **(M)** Property-based tests: net balances always sum to zero; shares always sum to the total; applying the simplified plan clears all balances.
6. **(M)** Middleware: Firebase token verification (stubbed with a test verifier in tests), request id, error envelope, zod validation, rate limit, idempotency.
7. **(M)** Authorization helpers `assertMember` and `assertAdmin` with negative tests.
8. **(M)** Ledger and expense endpoints (create/list/edit/delete expense with activity log), balances endpoint, simplified endpoint. Validate all invariants in a transaction.
9. **(S)** `GET /app/version`, `GET /health`.

**Exit criteria**
- [ ] Every acceptance scenario in `PRD.md` section 12 that only involves split and balance math (1 to 4, 9) passes as an automated test.
- [ ] Zero-sum and shares-sum properties hold across thousands of random cases.
- [ ] Non-members cannot read or write a ledger (tested).
- [ ] Duplicate request with the same `Idempotency-Key` creates one expense.
- [ ] API contract in `API.md` matches the implemented endpoints.

---

## Phase 2: Identity and friends

**Goal:** Real users can sign in, verify their phone, see a profile, add friends (app users and non-users), and invite non-users by SMS.

**Read first:** `PRD.md` 4.1 to 4.5, `ARCHITECTURE.md` 3.8, 3.9, 4.4, 5.5, 5.7, 5.8.

**👤 USER (do these before the agent wires auth)**
1. Create a Firebase project (dev). Add the Android app with package `com.splitup.app` and your **debug SHA-1**.
2. Enable **Google** and **Phone** sign-in. Add **test phone numbers** with fixed OTP codes for development.
3. Run `flutterfire configure` (or let the agent run it with you signed in).
4. Generate a **service account key** for the backend. Store it only in the server's environment or a git-ignored file. **Never paste it in chat or commit it.**

**Tasks**
1. **(M)** Firebase auth in the app: Google and email sign-in, phone entry, OTP verification, session persistence, logout (clears local database), route guards.
2. **(M)** Backend: Firebase Admin token verification, create-or-load user by verified phone, E.164 normalization, reject unverified phones.
3. **(M)** Profile: `GET/PATCH /users/me`, photo upload (storage decision: object storage or a server folder, document the choice), email change with re-verification, appearance setting local.
4. **(M)** Contacts: permission on tap, searchable picker, manual entry fallback, only selected contacts sent, number normalization.
5. **(M)** `POST /friends`: existing user path (bidirectional friendship, individual ledger, in-app notification), non-user path (placeholder user, `is_app_user: false`), duplicate detection, block and remove (with unsettled-balance guard).
6. **(S)** Invite popup: opens the device SMS app via `sms:` intent with the preset message and the website link; friend card shows "Not on app. Invite again."
7. **(M)** Nicknames: stored per viewer, mirrored locally, `displayNameFor` fed by real data, "Edit name" and reset, profile name caption, duplicate-name prompt.
8. **(M)** **Placeholder merge** on first verified sign-in with the matching number, with the merge summary explainer and inviter notification.
9. **(S)** Contact lookup endpoint with rate limits and minimal response.
10. **(M)** FCM setup: device token registration and unregistration, basic push for "added as friend."
11. **(M)** Home screen on real data: friends list, summary hero (zeros for now), notifications bell with real unread count.

**Exit criteria**
- [ ] New user: Google sign-in, OTP, lands on empty Home.
- [ ] Adding an app-user contact notifies them in-app and via push; adding a non-user opens the SMS app with the preset text.
- [ ] A placeholder merges correctly when that number signs up, and the inviter is notified.
- [ ] A nickname never appears in anything the friend sees (tested).
- [ ] Contacts permission denial still lets the user add a friend manually.
- [ ] **Checkpoint: release smoke test.** Build a **release APK**, add the release SHA-1 and SHA-256 to Firebase, install it by sideloading on 2 phones, and confirm **Google sign-in and phone OTP work**. Also confirm the Google consent screen is not stuck in "testing" mode for your friends. 👤 USER

---

## Phase 3: Individual ledger (expenses and confirmed settlements)

**Goal:** Two friends can record shared expenses and settle with the sender/receiver confirmation flow. This phase delivers the core promise.

**Read first:** `PRD.md` 4.4, 4.6, 4.10, 4.12, `APP_RULES.md`, `ARCHITECTURE.md` 5.1 to 5.4.

**Tasks**
1. **(M)** Add-expense sheet on real data: amount-first keypad, title, category, multi-payer, split type segmented control (equal, exact, percent, shares), "Not there" toggle, live per-person preview (client preview, server decides). Must pass shared vectors.
2. **(M)** Friend page on real data: balance direction summary, grouped expense list, "Also in" labels (empty until Phase 4/5), edit and delete expense with activity log.
3. **(S)** Expense detail with receipt-style card, activity log and **Dispute** action (notifies creator, flags expense, no balance change).
4. **(L)** Settlement lifecycle: create (sender only), pending, confirm, reject, cancel, **Outdated detection on open and on confirm with row locks**, partial settlements, overpayment blocked, audit events.
5. **(M)** **Resubmit** (one tap) with the "as is or change amount" prompt for Rejected, "No amount due anymore" handling, and the 24-hour re-notification guard.
6. **(S)** Placeholder receivers: creator confirms on their behalf, labeled **self-confirmed (unverified)**.
7. **(M)** Notifications feed on real data: inline Confirm and Reject, result states, Today/Yesterday/Earlier grouping, unread badge, mark all read, deep links, push for every type in `PRD.md` 4.12 that applies at this stage.
8. **(S)** Reminder job for pending settlements to receivers.
9. **(M)** Profile totals (you owe, you are owed, net) from real balances.
10. **(M)** Tests for acceptance scenarios 5, 6, 7 in `PRD.md` section 12, plus concurrency: two simultaneous confirms of the same request produce one result.

**Exit criteria**
- [ ] Two real phones: add an expense, see correct balances on both sides.
- [ ] Settle flow works end to end: sender taps Settle, receiver gets push, taps Confirm, both balances update; Reject leaves balances unchanged.
- [ ] Settle button never appears on a row where the user receives money.
- [ ] A pending request becomes Outdated after an expense changes the amount, and Resubmit offers the correct amount.
- [ ] Unverified-placeholder settlement is labeled correctly.
- [ ] **Checkpoint: first friends test.** 👤 USER deploys the backend and database to the chosen host (staging is fine) with HTTPS and backups, builds a release APK pointing to it, and invites 3 to 5 friends to try individual expenses. Collect bugs before Phase 4.

---

## Phase 4: Groups

**Goal:** Ongoing friend groups with admin rules, "Not there", dashboard charts, the node-and-link graph, simplification and group-to-individual offsets.

**Read first:** `PRD.md` 3.5, 4.7, 4.9, 4.11, `DESIGN.md` 10.4 and 10.6, `APP_RULES.md` (simplification and offsets), `ARCHITECTURE.md` 3.7 and 5.6.

**Tasks**
1. **(M)** Groups list on real data (WhatsApp-style rows, last activity, my balance) and the floating Create group button.
2. **(M)** Create group: name, photo, members from friends and contacts, creator is admin, non-app members get the SMS invite list on the success screen, app users get in-app notifications.
3. **(M)** Group roles and rules: admin-only rename, add and remove member, delete group; any member can add expenses; leaving or removal blocked while unsettled balances exist (`UNSETTLED_BALANCE`).
4. **(M)** Group expenses tab and add-expense with **"Not there"** (excluded members get zero share and cannot be payers).
5. **(M)** Group Dashboard tab: category donut, paid-vs-share bars per member, spending-over-time line (`fl_chart`, minimal styling per `DESIGN.md`).
6. **(L)** **Settlement graph** for real data: server returns nodes and links for **Simplified** and **Actual** modes; pending links dashed; node highlight and link detail sheet; layout in an isolate; text list alongside; `Semantics` labels.
7. **(M)** Group Settle tab: list plus graph, **Settle (amount)** only on rows where the user pays, same lifecycle as Phase 3 applied to the group ledger.
8. **(L)** **Offsets** (group with individual): suggestion in the group Settle flow showing exactly what is offset, atomic two-entry record under one offset id, one confirm/reject for both, Outdated check on **both** balances, remainder settled normally. Trips excluded.
9. **(S)** "Also in: <groups>" labels on the friend page.
10. **(M)** Tests for acceptance scenarios 3, 4 and 8, plus: removal blocked with unsettled balances, simplification never includes non-members, duplicate-name prompt in groups.

**Exit criteria**
- [ ] A 5-member group with 12 expenses shows at most 4 simplified payments, and the Actual toggle shows pairwise debts.
- [ ] Graph is readable with 6 and with 10 nodes on a phone, and every node has an avatar.
- [ ] Offset of Rs 60 against a Rs 100 group debt works: Rs 60 offset, Rs 40 settled normally; reject changes neither ledger; both entries confirm together or not at all.
- [ ] Non-admins cannot rename, add or remove members (tested).
- [ ] An absent ("Not there") member is never charged.

---

## Phase 5: Trips

**Goal:** Time-boxed, isolated trip ledgers with a budget, meter, dashboard, graph and completion state.

**Read first:** `PRD.md` 4.8, `DESIGN.md` 10.5, `ARCHITECTURE.md` 4.8.

**Tasks**
1. **(M)** Trips list on real data: Active and Completed segments, cards with member avatars and budget line, small Create button.
2. **(M)** Create trip: name, budget, optional dates, members by search, **"Add all members of an existing group"** (copies members, no live link), SMS invite list for non-app members, in-app notifications for app users.
3. **(L)** Trip dashboard: **budget gauge with the four levels** (under 60, 60 to 80, 80 to 100, over 100) and messages, budget slider plus editable number field, "remaining per day" when dates exist, category donut, daily spending bars, expense list, Add expense floating button, Edit (rename).
4. **(S)** Budget changes by the creator only, each written to the activity log.
5. **(M)** Budget warning notifications at 80 percent and 100 percent, sent once per threshold per trip.
6. **(M)** Trip add-expense with "Not there"; trip Settle tab reusing the graph and settlement lifecycle.
7. **(S)** Mark as completed (manual, prompted after the end date); completed trips still allow settlements.
8. **(M)** Trip isolation enforcement: no offsets, no cross-ledger balances, trip data absent from friend balances (tested).
9. **(S)** Tests for acceptance scenarios 9 and 12, plus: copied group members unaffected by later group edits.

**Exit criteria**
- [ ] A Rs 50,000 budget with Rs 38,400 spent shows the amber (60 to 80) state and correct per-day figure.
- [ ] Crossing 100 percent shows the over-budget state and sends one notification.
- [ ] No trip amount appears in any individual or group balance; no offset option exists inside trips.
- [ ] Marking a trip completed moves it to Completed and settlements still work.

---

## Phase 6: Polish and release

**Goal:** A stable, good-looking build that friends can download from the website and use daily.

**Read first:** `DEPLOYMENT.md`, `DESIGN.md` sections 11 to 12, `PRD.md` sections 8, 9, 13.

**👤 USER**
- Create the **release keystore**, back it up in two safe places, and never commit it. Add release SHA-1 and SHA-256 to the **prod** Firebase project.
- Set up the production backend, MySQL with daily backups (test one restore), domain and HTTPS.
- Register a domain and host the website. Confirm the Google sign-in consent screen is published for your friends.

**Tasks**
1. **(M)** Empty, loading and error states for every list and detail screen; offline banner "You're offline. Showing saved data."; friendly error messages from typed failures.
2. **(M)** Performance pass on a mid-range phone: limit blurred layers to 3 per screen, solid fills in lists, `RepaintBoundary` on glass, enable `reducedEffects` automatically when frame times are poor.
3. **(S)** Accessibility pass: contrast on glass in both themes, 48dp targets, font scaling to 130 percent, reduce-motion handling, graph semantics.
4. **(S)** In-app update check (`GET /app/version`), "Update available" banner and blocking "Please update" for unsupported versions.
5. **(S)** Account deletion ("Deleted user" anonymization), blocked users list, notification preferences, help and feedback link, app version row.
6. **(M)** Security review: authorization tests for every endpoint, rate limits verified, secrets audit, release build config (R8, no sensitive logging, backup rules).
7. **(M)** Website: landing page, screenshots (light and dark), **Download for Android** button with version and size, QR code, illustrated install guide (allow unknown sources, Play Protect "Install anyway"), privacy policy, contact email, HTTPS, correct APK content type.
8. **(S)** Release process: version code bump, signed release APK, attach to a release or object storage, update the version endpoint.
9. **(M)** Full manual regression using the checklist in `DEPLOYMENT.md` on 2 to 3 real phones with the **release APK**: Google sign-in, OTP, push, contacts, SMS invite, every acceptance scenario in `PRD.md` section 12.

**Exit criteria**
- [ ] All 13 acceptance scenarios in `PRD.md` section 12 pass (automated where possible, manual otherwise).
- [ ] A friend with a fresh phone can download from the website, install, sign in, verify the number and see expenses added for them.
- [ ] Backup restore has been tested at least once.
- [ ] No secrets in the repository, app bundle or logs.
- [ ] Release APK is signed with the backed-up keystore, version number incremented.

---

## Phase 7: Later (not for the first release)

Pick based on feedback from friends. Each item is independent.

| Item | Notes |
|---|---|
| **Offline editing with sync** | Local write queue (`pending_operations`), conflict rules (last write wins for edits, server wins on money validation), retries using idempotency keys. Hardest item, design carefully. |
| **UPI deep links** | Open a UPI app prefilled to pay a friend; settlement is still confirmed by the receiver. |
| Receipt photo attachments | Storage and size limits needed. |
| Export trip or group report as PDF | Server-side or on-device. |
| Recurring expenses | Rent, subscriptions. |
| Group archive and "settle all, start fresh" | Needs rules for old data. |
| Auto-confirm after N days (opt-in per group) | Only if reminders prove insufficient. |
| Google Play release | Removes install warnings and adds auto-updates; needs a developer account and review. |
| iOS | Apple developer account, push certificates, Firebase iOS setup. |
| Multi-currency | Needs exchange-rate decisions. |

---

## Release Checkpoints Summary

| After phase | Checkpoint | Who |
|---|---|---|
| 0 | Walk through every screen on a real phone | 👤 USER |
| 1 | Review test results for the money engine | 👤 USER + agent |
| 2 | **Release APK smoke test: Google sign-in and phone OTP on sideloaded phones** | 👤 USER |
| 3 | **First friends test** on a staging backend (individual expenses and settlements) | 👤 USER + 3-5 friends |
| 4 | Group beta with one real friend group | 👤 USER + friends |
| 5 | Real trip dry run with a small budget | 👤 USER + friends |
| 6 | Full regression, then share the website link | 👤 USER |

---

## Suggested Prompt to Start Each Phase (for Antigravity)

```
We are starting Phase <N> of SplitUp. Read docs/PRD.md, docs/ARCHITECTURE.md,
docs/DESIGN.md, docs/APP_FLOW.md and docs/PHASES.md (Phase <N> only), plus any
file listed under "Read first" for this phase.

Do not write code yet. First give me:
1. A short plan for this phase's tasks in order, with the files you will
   create or change.
2. Any ambiguity or conflict you found between the docs.
3. The 👤 USER steps you need me to finish before you begin.

After I approve, build task by task. Run the tests after each task. At the end
of the phase, report which exit criteria pass and which do not.
```

---

## Scope Guard

If a request during a phase belongs to a later phase, **record it in a `BACKLOG.md` file** and keep going. Do not expand the current phase. The product only works if the money engine (Phase 1) and the settlement flow (Phase 3) are right, so protect their schedule above all.