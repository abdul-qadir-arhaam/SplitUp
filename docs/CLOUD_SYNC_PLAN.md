# SplitUp - Cloud Synchronization & Multi-User Architecture Plan ☁️

## Executive Summary
Currently, while user credentials and accounts are stored in **Cloud TiDB MySQL**, all subsequent user activity (Friends, Groups, Trips, Expenses, Settlements, and Notifications) is saved strictly on the phone's local storage (`SharedPreferences`). 

As a result:
1. **Uninstalls or device switches wipe out all shared data.**
2. **Friends do not see expenses or group additions on their phones in real time.**
3. **In-app notifications are not delivered across users.**

All 19 relational database tables (`users`, `friendships`, `ledgers`, `ledger_members`, `expenses`, `expense_splits`, `settlements`, `notifications`, etc.) **already exist in your TiDB Cloud database**. This implementation plan outlines how to connect the backend and Flutter app to achieve **100% cloud persistence, multi-user real-time collaboration, and cross-device notifications**.

---

## 🏛️ Architecture Overview

```
                      ┌──────────────────────────────────────┐
                      │          Flutter Mobile App          │
                      │  (Offline-First Cache + Riverpod)    │
                      └──────────────────┬───────────────────┘
                                         │ Bearer Token HTTP API
                                         ▼
                      ┌──────────────────────────────────────┐
                      │     Node.js / Express Server         │
                      │      (Vercel Unified Serverless)     │
                      └──────────────────┬───────────────────┘
                                         │ Knex Query Builder
                                         ▼
                      ┌──────────────────────────────────────┐
                      │       TiDB Cloud MySQL Database      │
                      │ (19 Tables: Users, Ledgers,          │
                      │  Expenses, Splits, Notifications)    │
                      └──────────────────────────────────────┘
```

---

## 📅 Phased Implementation Plan

### Phase 1: Backend MySQL Data Layer (Server-Side Persistence)
Connect the backend Express modules from in-memory arrays to Knex queries against the existing MySQL tables.

1. **Friendships & Blocks (`backend/src/modules/friends/`):**
   - Save friendships in the MySQL `friendships` table: `(owner_user_id, friend_user_id, individual_ledger_id, nickname, contact_name, created_at)`.
   - On invite/add: if the phone number doesn't exist, create a placeholder user in `users`; if it does exist, create reciprocal friendship links.
   - When a friend signs up with that phone number, the account automatically claims their placeholder ledgers and notifies the inviter.

2. **Ledgers (Groups & Trips) (`backend/src/modules/ledgers/`):**
   - Save groups and trips in the `ledgers` table (`type: 'GROUP' | 'TRIP' | 'INDIVIDUAL'`).
   - Save member associations in `ledger_members` (`ledger_id`, `user_id`, `role: 'ADMIN' | 'MEMBER'`).

3. **Expenses & Splits (`backend/src/modules/expenses/`):**
   - Save each expense in `expenses` (`id`, `ledger_id`, `title`, `total_paise`, `split_type`, `created_by`, etc.).
   - Save payers in `expense_payers` (`expense_id`, `user_id`, `paid_paise`).
   - Save splits in `expense_splits` (`expense_id`, `user_id`, `owed_paise`).

4. **Settlements & Offsets (`backend/src/modules/settlements/`):**
   - Save payment requests and confirmations in `settlements` (`from_user_id`, `to_user_id`, `amount_paise`, `status: 'PENDING' | 'CONFIRMED' | 'REJECTED'`).

5. **Cloud Notifications Store (`backend/src/modules/notifications/`):**
   - Save all notifications in the `notifications` table:
     - `id`, `user_id` (recipient), `type`, `payload` (JSON), `action_state`, `read_at`, `created_at`.

---

### Phase 2: Automatic Cross-User Notification Dispatching
When an action occurs on the server, automatically dispatch notifications to the relevant participants in MySQL:

1. **When User A adds Friend B:**
   - If Friend B is already registered $\to$ Friend B receives `FRIEND_ADDED` notification ("User A added you as a friend").
   - If Friend B joins the app later $\to$ User A receives `FRIEND_JOINED` notification ("Your friend B just joined SplitUp!").

2. **When User A adds an expense in a Group / Trip / Individual Ledger:**
   - All participants whose `owed_paise > 0` (excluding creator) immediately receive `EXPENSE_ADDED` notification in their notifications feed:
     *"User A added an expense of ₹1,200 in [Trip/Group Name]. Your share is ₹400."*

3. **When User A requests or records a settlement:**
   - The counterparty receives `SETTLEMENT_REQUESTED` notification with interactive **Confirm / Decline** action buttons.
   - When confirmed or declined $\to$ User A receives `SETTLEMENT_CONFIRMED` or `SETTLEMENT_REJECTED` notification.

---

### Phase 3: Flutter App API Client & Cloud Synchronization
Upgrade the Flutter app to maintain an **offline-first cache with cloud sync** so the app remains fast and responsive while guaranteeing 100% data persistence.

1. **Central HTTP Client (`core/network/api_client.dart`):**
   - Attaches `Authorization: Bearer <token>` to all requests.
   - Automatically handles base URL switching via [`ApiConfig.getBaseUrl()`](file:///c:/Users/Nasir%20Sada/Desktop/splitup/app/lib/core/config/api_config.dart).

2. **Cloud-Synced `FriendsRepository`:**
   - `fetchFriends()`: Queries `GET /v1/friends`. Updates local cache for offline viewing.
   - `addFriend()`: Sends `POST /v1/friends` to the server; adds the returned model to memory and local storage.

3. **Cloud-Synced `GroupsRepository` & `TripsRepository`:**
   - `fetchGroups()` / `fetchTrips()`: Queries `GET /v1/ledgers?type=GROUP` and `GET /v1/ledgers?type=TRIP`.
   - `createGroup()` / `createTrip()`: Sends `POST /v1/ledgers` with member list. All added members will see the group on their phones immediately.

4. **Cloud-Synced `ExpensesRepository`:**
   - `fetchExpenses(ledgerId)`: Queries `GET /v1/expenses?ledgerId=<id>`.
   - `createExpense()`: Sends `POST /v1/expenses` with payers and splits. Server computes net balances and broadcasts notifications.

5. **Cloud-Synced `NotificationsRepository`:**
   - `fetchNotifications()`: Queries `GET /v1/notifications`.
   - `markRead()` / `markAllRead()`: Sends `PATCH /v1/notifications/:id/read` and `POST /v1/notifications/mark-all-read`.
   - Periodic background check / pull-to-refresh to pull new notifications from friends.

---

### Phase 4: Verification & Multi-Device Testing

1. **Test Scenario 1 (Reinstall Persistence):**
   - Add friends, create a group, and log an expense.
   - Delete/uninstall the app on phone.
   - Reinstall $\to$ Log in $\to$ Verify 100% of friends, groups, expenses, and history reload seamlessly from MySQL.

2. **Test Scenario 2 (Two Different Devices / Accounts):**
   - Log in as User 1 on Device A.
   - Log in as User 2 on Device B.
   - User 1 adds User 2 as a friend $\to$ Device B gets instant in-app notification.
   - User 1 creates an expense in a shared group $\to$ Device B shows the expense and updated balance.
   - User 2 initiates settlement $\to$ Device A sees settlement request and confirms.

---

### Phase 5: Release via OTA In-App Update
1. Bump version to `v1.0.4+5` in [`pubspec.yaml`](file:///c:/Users/Nasir%20Sada/Desktop/splitup/app/pubspec.yaml).
2. Build release APK: `flutter build apk --release --split-per-abi`.
3. Deploy to Vercel and push OTA notification.
4. Users update directly through their Profile tab with 1 tap.

---

## 🔒 Safety & Non-Breaking Guarantees
- **No breaking changes:** The offline cache will remain as a fallback so the app works even when network connectivity is intermittent.
- **Data safety:** All queries use transactions with foreign key safety to prevent corrupted states.
