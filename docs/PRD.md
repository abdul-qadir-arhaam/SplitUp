# SplitUp: Product Requirements Document (PRD)

> **Tagline:** Split up the bill, not the friendship.
> **Platform:** Android (Flutter). iOS later.
> **Distribution:** Signed APK downloaded from the product website.
> **Document purpose:** Single source of truth for the Antigravity agent. Read this file together with `DESIGN.md` (visual language), `APP_FLOW.md` (screen navigation) and the other project files before writing code. If anything here conflicts with a screen design, the rules in this PRD win for behavior, and `DESIGN.md` wins for visuals.

---

## 1. Product Overview

SplitUp is a money-centric expense-sharing app for friends. It tracks who paid, who shared, and who owes whom, across three kinds of ledgers: **Individual (1-to-1)**, **Group** (ongoing friend circles) and **Trip** (time-boxed, with a budget). Settlements are confirmed by both parties, so nobody can dispute "I never received that money."

### 1.1 Problem
When several people pay for shared expenses (for example a Rs 1,200 dinner where A paid 200, B paid 600 and C paid 400), working out who owes whom becomes confusing, and it gets worse as expenses accumulate across outings, groups and trips.

### 1.2 Goals
1. Record shared expenses quickly (amount-first, a few taps).
2. Always show a correct, explainable answer to "how much do I owe or get back, and from whom."
3. Make settling clear with a minimal number of payments and a two-party confirmation.
4. Show complex group and trip settlements visually as a node-and-link graph.
5. Give trips a budget with a meaningful meter and dashboard charts.
6. Feel premium and minimal (Apple-style glassmorphism, money-centric details), and clearly better than Splitwise.

### 1.3 Non-goals (version 1)
- No in-app money transfer or payment processing. Payments happen outside the app (cash, UPI, bank) and are only *recorded*.
- No iOS build, no web client.
- No multi-currency (INR only).
- No receipt scanning/OCR.
- No changing phone number after signup.
- No cross-linking of trip balances into individual or group balances (see 4.4).

### 1.4 Target users
Friend circles in India (students, colleagues, roommates, travel buddies) who share expenses regularly. Primary persona: a person who organizes outings and gets stuck tracking dues. Secondary persona: a friend invited via SMS who has never used the app.

---

## 2. Tech Stack (fixed decisions)

| Layer | Choice |
|---|---|
| Mobile app | Flutter (Android first), Material 3 base with custom glass theme |
| State management | Riverpod (or Bloc, pick one and stay consistent) |
| Local storage | SQLite via `drift` (cache, drafts, private nicknames, settings) |
| Charts | `fl_chart` |
| Graph view | Custom painter (`CustomPaint`) for nodes and links |
| Backend | Node.js (Express or NestJS), REST + JSON, TypeScript preferred |
| Database | MySQL 8 (InnoDB), money stored as **integer paise** |
| Auth | Firebase Authentication (Google sign-in, email, phone OTP) |
| Push | Firebase Cloud Messaging |
| Token verification | Firebase Admin SDK on the backend |
| Hosting | Backend and MySQL on a cloud service or VPS with HTTPS and daily backups |
| Website | Static site with download page for the APK |

**Local-first scope (important):** MySQL on the server is the source of truth. The app keeps a SQLite cache for fast screens and basic offline viewing. Full offline *editing* with sync is a later phase (see section 14). Version 1 must work online with graceful offline reading.

---

## 3. Core Concepts

### 3.1 Ledger
All three modes are "ledgers" with members and expenses. The mode adds feature flags.

| | Individual | Group | Trip |
|---|---|---|---|
| Members | Exactly 2 | Many, ongoing | Many, time-boxed |
| Budget | No | No | Yes (required) |
| Dashboard charts | No | Yes | Yes |
| Settlement graph | No | Yes | Yes |
| Date range / status | No | No | Optional dates, Active or Completed |
| Offset with Individual ledger | Source of offsets | Yes | **No** |
| Has an admin | No | Yes (creator) | Creator acts as owner |

An individual ledger is an implicit ledger of two people created automatically when two users become friends.

### 3.2 Expense
An expense has:
- **Payers:** one or more members, each with the amount they paid (payer amounts must sum to the expense total).
- **Participants (split):** members who share the cost, with how it is shared.
- **Split types:** `EQUAL`, `EXACT` (amounts), `PERCENT`, `SHARES`.
- Title, total amount, category, date, optional note.
- Members marked **"Not there"** are excluded from the split and cannot be a payer for that expense.

### 3.3 Net balance (the heart of the system)
For each member in a ledger:

`net = total paid by member - total share owed by member + settlements received - settlements paid`

- Positive net: the member is owed money. Negative net: the member owes money.
- **Balances are always computed from expense and settlement records, never stored as editable values.** Any cached balance must be derivable and rebuildable.
- Only **confirmed** settlements affect balances.

### 3.4 Money handling
- All amounts are integers in **paise** (Rs 12.50 = 1250). Never use floating point for money.
- Display in Indian number format with the rupee symbol, for example `Rs 1,20,000` or `₹1,20,000`.
- **Rounding rule:** when a split does not divide evenly, distribute the leftover paise one at a time in a deterministic order (by member id) so the shares always sum exactly to the total.

### 3.5 Debt simplification (Group and Trip only)
Algorithm: compute each member's net balance, then repeatedly match the largest debtor with the largest creditor, settling the smaller of the two amounts. This yields at most (n - 1) payments.
- The graph offers a toggle: **Actual** (direct pairwise debts that explain why) and **Simplified** (minimum payments that tell people what to do).
- Simplification never crosses ledgers. It only uses members of that group or trip.

---

## 4. Functional Requirements

Requirement IDs are for traceability in tests and tasks. Priority: **P0** must ship in v1, **P1** should ship in v1, **P2** later.

### 4.1 Authentication and identity

| ID | Requirement | Priority |
|---|---|---|
| AUTH-1 | Sign in with Google or email through Firebase Authentication. | P0 |
| AUTH-2 | After first sign-in, user must verify a mobile number with an OTP (Firebase phone auth). The app cannot be used until verified. | P0 |
| AUTH-3 | The **normalized phone number** (E.164, for example +919876543210) is the unique identity key for a user. Email and Google are only login methods. | P0 |
| AUTH-4 | The app sends the Firebase ID token with every API request. The backend verifies it with the Firebase Admin SDK and maps it to a user row by phone number. | P0 |
| AUTH-5 | Persistent session. Logout asks for confirmation and clears local session data. | P0 |
| AUTH-6 | Delete account: personal data is removed, and the user appears as "Deleted user" in other people's historical expenses so balances stay correct. | P1 |
| AUTH-7 | Phone number cannot be changed in v1. Email change requires re-verification. | P0 |

### 4.2 Placeholder users and merging
- When a user adds a contact who is **not** on the app, the backend creates a **placeholder user** tied to that normalized phone number, created by the adding user.
- Expenses and ledgers can include placeholders immediately.
- When someone signs up and verifies a number matching a placeholder, the placeholder **merges into the real account** and all history becomes visible to them.
- On first launch after a merge, show an explainer: "X has added you to N expenses totalling Rs Y."
- The inviter gets an in-app notification: "Rahul joined. Your balances are now live."

### 4.3 Friends and contacts

| ID | Requirement | Priority |
|---|---|---|
| FR-1 | Home screen shows a **Add friends** button. If the user already has friends, the friends list is shown on the home screen itself. | P0 |
| FR-2 | Add friends opens the device contact list with search. Request contacts permission **only** when the user taps Add friends, with a short explanation. Provide manual entry (name and phone) if permission is denied. | P0 |
| FR-3 | Only the contacts the user **selects** are sent to the server. Never upload the full address book. | P0 |
| FR-4 | **No acceptance step.** Adding a friend adds them immediately to the friends list. | P0 |
| FR-5 | If the friend **is** an app user: add directly and send them an **in-app notification** (and a push). No SMS. The notification offers Remove and Block. | P0 |
| FR-6 | If the friend is **not** an app user: add as a placeholder, then show a popup "Invite your friend through SMS". Tapping the button opens the **device SMS app** with a preset message and the download-page link. SMS is sent by the user from their own phone. | P0 |
| FR-7 | The friend card shows "Not on app. Invite again" for non-users and can reopen the invite popup. Never claim "Invited" as confirmed, because send cannot be detected. | P0 |
| FR-8 | SMS invite message: `"<Inviter name> invited you to join SplitUp to split expenses easily: <website download link>"`. The link must go to the website download page, not directly to the APK. One recipient per message. | P0 |
| FR-9 | If a contact is already a friend, say so and do not duplicate. | P0 |
| FR-10 | A friend can be removed only when there are **no unsettled balances** with them. | P0 |
| FR-11 | Block: a blocked user cannot add expenses with you or invite you to groups or trips. Blocked users list lives in Profile. | P1 |
| FR-12 | Contact lookup (is this number a user?) is rate-limited and returns only: is-user flag, display name and photo. Never expose email or other details. | P0 |

### 4.4 Friend page (Individual ledger)
- Header: avatar, display name, and small grey "Profile name: <name>" when a nickname is set.
- Summary: who owes whom and how much (for example "Rahul owes you Rs 1,240").
- **Settle** button appears **only** when the current user is the one who must pay.
- Chips showing shared groups and trips ("Also in: Friday Gang, Goa Trip"). These are **labels only**. No trip or group amounts are added to the individual balance.
- Expense list grouped by date, with an **Add expense** floating button.
- Edit name action (see 4.5).

### 4.5 Private nicknames
- Each user sees each friend under a name only they control.
- **Priority:** (1) manual nickname, (2) name saved in the phone contacts, (3) the friend's own profile name.
- Stored per friendship per viewer. **Never shared** with the friend or shown in anything sent to them, including notifications and SMS.
- Reset button returns to the contact name. The profile name is always shown in small grey text beneath.
- A single `displayNameFor(viewer, person)` function must be used everywhere a person's name is rendered (lists, graph, expenses, notifications, split screens, search).
- In a group or trip, if two members resolve to the same visible name, show a gentle prompt "Two members are named Abdul. Give one a nickname?" and a small disambiguator (last two digits of number) as a fallback. Avatars with initials or photos must appear on every graph node.
- If the phone contact name changes later, follow it unless a manual nickname exists.

### 4.6 Individual expenses
- Add expense with a friend: amount-first input, title, category, who paid, how split (equal, exact, percent, shares).
- Regular expenses need **no confirmation** from the other person.
- Every create, edit and delete is written to an **activity log** visible to participants.
- Participants can **Dispute** an expense. This notifies the creator and flags the expense. It does not change balances.

### 4.7 Groups

| ID | Requirement | Priority |
|---|---|---|
| GRP-1 | Groups tab lists groups WhatsApp-style (avatar, name, last activity, my balance in the group). Create group is a floating button. | P0 |
| GRP-2 | Create group: name, optional photo, members from contacts and friends. The creator is the **admin**. | P0 |
| GRP-3 | App-user members get an in-app notification. Non-app members are shown an invite list with per-person SMS invite buttons (device SMS app). | P0 |
| GRP-4 | Any member can add expenses. Only admins can rename the group, add or remove members, and delete the group. | P0 |
| GRP-5 | A member cannot leave or be removed while they have unsettled balances in the group. | P0 |
| GRP-6 | Group page has tabs: **Expenses**, **Dashboard**, **Settle**. | P0 |
| GRP-7 | Dashboard: donut chart by category, paid-vs-share bars per member, spending-over-time line. | P1 |
| GRP-8 | **"Not there" toggle** when adding an expense: the marked member is excluded from the split and cannot be a payer. Everyone is included by default. | P0 |
| GRP-9 | Settle tab: list of settlements and a **node-and-link graph** (see 4.9). | P0 |
| GRP-10 | A group can be archived or "settled and started fresh" when all balances are zero. | P2 |

### 4.8 Trips (isolated)

| ID | Requirement | Priority |
|---|---|---|
| TRP-1 | Trips tab lists trips under **Active** and **Completed**, with a small Create button. | P0 |
| TRP-2 | Create trip: name, budget, optional dates, members. Members are added by searching friends and contacts, and by **"Add all members of an existing group"**, which **copies** members into the trip (later group changes do not affect the trip). | P0 |
| TRP-3 | App-user members get in-app notifications. Non-app members get the SMS invite flow. | P0 |
| TRP-4 | Trip dashboard: budget meter, budget slider with an editable number field, category donut, daily spending bars, expense list, **Add expense** floating button, **Edit** (rename trip). | P0 |
| TRP-5 | **Budget meter levels:** under 60 percent spent: green "on track"; 60 to 80: amber heads-up; 80 to 100: orange warning with remaining amount; over 100: red with the amount over budget. With dates, also show "remaining per day." | P0 |
| TRP-6 | Budget can be changed by the creator via slider or number field. Each change is written to the activity log. | P0 |
| TRP-7 | Status: Active or Completed. Creator can "Mark as completed" (prompted after the end date). A completed trip still allows settlements. | P0 |
| TRP-8 | Settle tab with list and node-and-link graph, same behavior as groups. | P0 |
| TRP-9 | Same "Not there" exclusion as groups. | P0 |
| TRP-10 | Trips never connect to individual or group ledgers: **no offsets, no combined balances**. | P0 |

### 4.9 Settlement graph (Groups and Trips only)
- Node = person (circular avatar with ring). Ring color: emerald if owed money, terracotta if owes. Node size reflects net amount.
- Link = arrow from payer to receiver. Thickness reflects amount. Monospaced amount label on the arrow.
- Toggle: **Simplified** (default) and **Actual**.
- **Pending** settlements render as **dashed** arrows. Confirmed ones are solid and no longer appear as debt.
- Tapping a node highlights only that person's links. Tapping an arrow shows its details and, if the current user is the payer, the Settle action.
- Always show a text list beside or below the graph (accessibility and clarity).
- Must stay readable for up to about 10 nodes. Beyond that, offer a list-first fallback.
- The graph is **not** shown for individual (1-to-1) ledgers.

### 4.10 Settlement flow (critical rules)

Statuses: `PENDING`, `CONFIRMED`, `REJECTED`, `OUTDATED`, `CANCELLED`.

1. Only the person who **sends** money creates a settlement. A **Settle (amount)** button appears **only** on rows where the current user must pay someone. It never appears on rows where the user receives money.
2. Creating a settlement sends a confirmation notification to the **receiver**.
3. The receiver sees exactly two buttons: **Confirm** and **Reject**. No reason text.
4. Only **CONFIRMED** settlements change balances. Pending ones are displayed but not counted.
5. The sender may **cancel** a request before the receiver responds.
6. **Stale amounts, option (a):** when the receiver opens or acts on a request, the backend re-checks current balances. If the amount is no longer valid, the request becomes **OUTDATED**, the sender is notified, and nothing changes in balances.
7. **Partial settlements** are allowed up to the amount owed. Overpayment is blocked.
8. **Resubmit (one tap):** on Rejected or Outdated requests the sender sees **Resubmit**. It re-reads current balances and creates a **new** record pre-filled with the current amount. The old record is never edited and is linked to the new one. For Rejected requests, prompt "Resubmit as is, or change the amount?" If the balance is now zero or reversed, show "No amount due anymore" instead of the button. Do not re-notify the receiver for the same amount within 24 hours.
9. **Account-less (placeholder) receivers:** the **creator** (the user who added that friend) confirms on their behalf. The record is labeled **self-confirmed (unverified)**. If the friend later joins, they see these records.
10. Method field: `CASH`, `UPI`, `OFFSET`, `OTHER` (informational only).
11. Every status change is stored with timestamp and actor (audit trail).

### 4.11 Offsets (Group with Individual ledger only)
- In a group's Settle flow, if the user must pay person X and an individual balance with X exists in the opposite direction, offer: "Rahul owes you Rs 100 individually. Use it to offset?"
- Offset amount = `min(group amount owed, individual amount available)`. Any remainder is settled normally.
- An offset creates **two linked entries** (one in the group ledger, one in the individual ledger) under one **offset id**, as one atomic **pending** request.
- The receiver confirms or rejects the **whole offset as one unit**. Never one side without the other. Done inside a single database transaction.
- At confirmation time, re-check **both** balances. If either changed, the offset becomes **OUTDATED**.
- Offsets are always user-initiated suggestions, never automatic.
- Show exactly what is being offset before the user confirms.
- Trips are excluded.

### 4.12 Notifications
- Bell icon at the top right of Home, Groups and Trips, with an unread-count badge.
- Notification page: one feed, newest first, grouped Today, Yesterday, Earlier.
- **Actionable items have inline buttons** (Confirm/Reject for settlements and offsets, Remove/Block for friend adds).
- After acting, the item shows the result ("You confirmed Rs 450 from Aman") and stays in the feed.
- Types: added as friend; added to group or trip; settlement requested; settlement confirmed; settlement rejected; request outdated; offset requested; offset result; expense disputed; friend joined; trip budget warning (80 percent and over 100 percent); member removed.
- Pending actionable items stay visually distinct and are not buried by older informational items.
- "Mark all as read." Empty state: "You're all caught up."
- Every notification is also sent as an FCM **push** so urgent items are not missed.

### 4.13 Profile
- Opens from the bottom nav. Shows avatar, name, email, phone (read-only).
- Summary: **total you owe**, **total you are owed** (separate lines) and net.
- Editable: name, profile picture (gallery or camera, circular crop, remove falls back to initials), email (re-verification required).
- Appearance: **Light, Dark, System default**.
- Also: notification preferences, blocked users, delete account, help and feedback link, app version.
- Logout button at the bottom, styled in the "owe" color, with a confirmation dialog.

### 4.14 Navigation
- Bottom floating glass nav bar with four tabs, in order: **Home (Friends), Groups, Trips, Profile**.
- Bar visible on the four main screens, hidden on deeper screens (graph, expense detail, add expense, create flows).
- Tab badge when something needs action.
- Home is the default landing screen. The Groups tab contains only groups and a Create group button.

---

## 5. Key User Flows (summary)

1. **Onboarding:** Welcome, Google or email, mobile number, OTP, Home (empty state).
2. **Add friend:** Home, Add friends, contact picker, select, Add. App user: in-app notification. Non-user: invite popup, device SMS app opens with preset message.
3. **Individual expense:** Friend card, Add expense, save, balance updates, friend page shows who pays whom.
4. **Group:** Groups tab, Create group, name and members, invite non-users, group page, add expense (with "Not there"), Dashboard, Settle tab graph.
5. **Trip:** Trips tab, Create trip (name, budget, members or copy group), trip dashboard, add expenses, adjust budget, Settle tab graph, mark completed.
6. **Settle:** Settle tab, Settle (amount) on a row where I pay, pending, receiver gets notification, Confirm, balances update. Or Reject, Resubmit.
7. **Offset:** Group Settle, "use individual balance", pending, receiver Confirm, both ledgers update.

Detailed screen-by-screen navigation lives in `APP_FLOW.md`.

---

## 6. Data Model (conceptual)

Full schema is in `DATABASE.md`. Entities:

- **users** (id, phone_e164 unique, name, email, photo, is_placeholder, created_by, firebase_uid, status)
- **friendships** (user_id, friend_id, nickname, contact_name, blocked, created_at)
- **ledgers** (id, type: INDIVIDUAL/GROUP/TRIP, name, photo, budget_paise, start_date, end_date, status, created_by)
- **ledger_members** (ledger_id, user_id, role, joined_at)
- **expenses** (id, ledger_id, title, total_paise, category, date, note, created_by, deleted_at)
- **expense_payers** (expense_id, user_id, paid_paise)
- **expense_splits** (expense_id, user_id, owed_paise, included)
- **settlements** (id, ledger_id, from_user, to_user, amount_paise, method, status, offset_id, replaced_by, created_by, confirmed_by_creator_on_behalf, created_at)
- **settlement_events** (settlement_id, status, actor, at)
- **activity_log** (ledger_id, actor, action, payload, at)
- **notifications** (id, user_id, type, payload, action_state, read_at, created_at)
- **disputes** (expense_id, raised_by, created_at)
- **device_tokens** (user_id, fcm_token)

Balances and simplified payment plans are **computed** from these tables.

---

## 7. API Surface (summary)

Detailed contract in `API.md`. Main groups:
`/auth`, `/users/me`, `/contacts/lookup`, `/friends`, `/ledgers` (groups, trips, individual), `/ledgers/:id/expenses`, `/ledgers/:id/balances`, `/ledgers/:id/simplified`, `/settlements`, `/offsets`, `/notifications`, `/devices`, `/app/version`.

All endpoints require a valid Firebase ID token (except the public version-check). All money in paise. All writes that touch more than one table run in a transaction.

---

## 8. Non-Functional Requirements

### 8.1 Correctness
- Net balances must always equal the sum of payer amounts minus owed amounts plus confirmed settlements. Backend unit tests must cover: equal, exact, percent and shares splits; rounding; multiple payers; "Not there"; simplification; partial settlement; offsets; Outdated detection; placeholder merge.
- Sum of all net balances in a ledger must always be exactly zero.

### 8.2 Performance and UX
- Home and lists open instantly from the local cache, then refresh.
- Glass blur (`BackdropFilter`) is limited to a few surfaces (hero card, bottom nav, sheets, top bars). **List rows are solid tinted fills** to keep mid-range Android phones smooth.
- Target 60 fps scrolling on a mid-range device.

### 8.3 Security and privacy
- HTTPS only. Firebase ID token verified on every request.
- Secrets (database credentials, Firebase service account key) live only on the server in environment variables and are never committed or shipped in the app.
- Users can only read ledgers they belong to. Authorization is checked on every endpoint.
- Rate-limit contact lookups and settlement creation.
- Privacy policy page on the website. Nicknames never leave the user's side.

### 8.4 Accessibility
- Minimum 48dp tap targets, sufficient text contrast on glass surfaces (amount panels use higher-opacity glass), graph always paired with a text list, dark and light themes.

### 8.5 Offline behavior (v1)
- Cached data viewable offline. Writes require a connection in v1 and show a clear "You're offline" state. True offline editing with sync is phase 5.

---

## 9. Distribution and Release

- Signed release **APK** built with a private keystore (backed up, never committed). Package name fixed: `com.splitup.app`.
- Register **release SHA-1 and SHA-256** in Firebase so Google sign-in and phone auth work in release builds.
- Website provides: download button with version and size, QR code, step-by-step install guide ("Allow install from this source," Play Protect "Install anyway"), screenshots, privacy policy, contact email.
- **In-app update check:** on launch, call the version endpoint. If a newer version exists, show "Update available" linking to the website download page. Increase version code with every release.
- Test OTP login and Google sign-in on real devices using the **release APK** before inviting users.

---

## 10. Design Requirements

- Minimal, premium, Apple-style glassmorphism over a deep green-black base with blurred color blobs; light mode variant on warm off-white. Full details in `DESIGN.md`.
- **Color meaning:** emerald means money you will receive; terracotta means money you owe; brass is for accents and budget. Color is never decorative.
- Money amounts use a monospaced face with tabular figures. Manrope for UI text.
- Money-themed details: wallet-card balance panel, faint ledger lines in lists, receipt-style edge on expense details.
- Thin line icons, no emoji. One primary action per screen.
- Must **not** look like a generic AI-generated UI (no purple gradients, no neon glow, no stacked identical cards without hierarchy).

---

## 11. Build Phases

| Phase | Scope |
|---|---|
| **0. Foundations** | Flutter project, theme (light and dark), shared widgets, mock data, navigation shell matching `APP_FLOW.md` |
| **1. Backend core** | MySQL schema, Firebase token verification, net-balance engine with tests |
| **2. Identity and friends** | Auth and OTP, profile, contacts, friends, placeholders, nicknames, SMS invite flow |
| **3. Individual ledger** | Expenses, activity log, disputes, settlement with confirmation, notifications and push |
| **4. Groups** | Groups, admin rules, "Not there", dashboard, graph, simplification, offsets |
| **5. Trips** | Trips, budget meter and slider, dashboard, graph, completed state |
| **6. Polish and release** | Empty states, error states, update check, performance pass, release APK and website |
| **7. Later** | Offline editing with sync, UPI deep links, receipts, PDF export, recurring expenses, iOS, Play Store |

Each phase must be usable on its own.

---

## 12. Acceptance Criteria (key scenarios)

1. **Basic split:** A paid 200, B paid 600, C paid 400 on a Rs 1,200 dinner split equally. Result: only "A pays B Rs 200."
2. **Rounding:** Rs 1,000 split 3 ways yields shares summing exactly to 100000 paise.
3. **Not there:** Excluding a member from a Rs 900 expense among 3 yields Rs 450 each for the other two, and nothing for the excluded person.
4. **Simplification:** A group with 5 members and 12 expenses shows at most 4 simplified payments, and the toggle shows the actual pairwise debts.
5. **Settlement:** Sender taps Settle, receiver gets a notification, Confirm updates balances, Reject leaves balances unchanged, balances only change on Confirm.
6. **Button visibility:** The Settle button appears only on rows where the current user pays.
7. **Outdated:** A pending Rs 100 settlement becomes OUTDATED if a new expense reduces the owed amount before the receiver confirms. The sender can Resubmit with the correct amount.
8. **Offset:** Group debt Rs 100 to Rahul with Rahul owing the user Rs 60 individually: offset Rs 60, pay Rs 40 normally. Confirming applies both ledger entries atomically. Rejecting changes neither.
9. **Trip isolation:** No trip amount ever appears in an individual or group balance, and no offset option appears in trips.
10. **Nickname privacy:** Renaming a friend changes the name only on the renaming user's device and never appears in the friend's notifications.
11. **Placeholder merge:** After a non-user signs up with the same verified number, all previously logged expenses with them appear and the inviter is notified.
12. **Budget meter:** A Rs 50,000 budget with Rs 38,400 spent shows the 60 to 80 percent state (amber) and a per-day remaining figure when dates exist.
13. **Release:** A friend can download the APK from the website, install it, sign in with Google, verify their number with OTP and see their added expenses.

---

## 13. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Wrong balances destroy trust | Compute from records, heavy unit tests, zero-sum assertion |
| Offline sync complexity | Defer to phase 7, ship online-first with cache |
| Phone OTP behavior on sideloaded APK | Test the release APK early on real phones |
| Google sign-in left in testing mode | Check consent screen publishing status before inviting friends |
| Glass effect slows low-end phones | Limit blur to key surfaces, solid fills in lists |
| Unwanted adds and balances without consent | Remove and Block in notification, Dispute action, activity log |
| Lost signing keystore | Back up keystore and passwords in two safe places |
| SMS invite cannot confirm send | Show neutral "Not on app. Invite again" state |

---

## 14. Open Decisions (defaults assumed unless changed)

1. **Hosting:** cloud service or VPS (not a home computer). Default: managed cloud with daily MySQL backups.
2. **State management:** default Riverpod.
3. **Offline editing:** deferred to phase 7.
4. **UPI deep links** for settling: deferred (P2), the method field is informational in v1.
5. **Auto-confirm of unanswered settlements after N days:** not in v1. Reminder notifications only.
6. **Group archive / fresh start:** P2.

---

## 15. Glossary

- **Ledger:** a container of members and expenses (individual, group or trip).
- **Net balance:** what a member is owed (positive) or owes (negative) after expenses and confirmed settlements.
- **Simplified settlement:** the minimum set of payments that clears all balances.
- **Offset:** settling a group debt using an opposite individual balance, with no real money moving.
- **Placeholder user:** a not-yet-registered person tied to a phone number.
- **Outdated:** a pending request whose amount is no longer valid.
- **Paise:** 1/100 of a rupee, the unit for all stored money.

---

## 16. Companion Files (to be provided)

`DESIGN.md`, `APP_FLOW.md`, `APP_RULES.md` (settlement and balance logic), `DATABASE.md`, `API.md`, `ARCHITECTURE.md`, `TASKS.md` (phased build checklist), `DEPLOYMENT.md`, `AGENT_INSTRUCTIONS.md`.