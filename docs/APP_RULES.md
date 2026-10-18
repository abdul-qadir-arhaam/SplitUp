# SplitUp: APP_RULES.md

> Authoritative business and domain rules for SplitUp balance, settlement, and expense lifecycle.

---

## Settlement rules

**R1 IDs:**
Only the server creates settlement ids. The app never invents one. The app stores only what the server returns and mirrors the server list.

**R2 Create:**
Caller must be the sender (`from_user`) and both users must be members of the ledger. `net` values come from the SQL balance query (confirmed settlements only). Valid only if:
- `net(sender) < 0`
- `net(receiver) > 0`
- `0 < amount <= min(-net(sender), net(receiver))`
This single rule applies to individual, group, and trip ledgers.

**R3 One pending:**
At most ONE PENDING settlement per `(ledger, sender, receiver)`. A second create returns `409 CONFLICT` with the existing settlement, and the app shows that existing one. The endpoint also honors an `Idempotency-Key` header.

**R4 Balance invariant:**
Pending settlements never change balances. Only `CONFIRMED` settlements change balances.

**R5 Confirmation & Lifecycle:**
- **Confirm** (by receiver, or the person who added a placeholder receiver, labelled self-confirmed): executed in one database transaction. Locks the settlement row and the ledger's member rows with `FOR UPDATE`, and re-runs R2.
  - If now invalid: status set to `OUTDATED` (no balance change).
  - Else: status set to `CONFIRMED`, writes `settlement_events`, marks the receiver's notification `action_state` as `DONE` with `action_result: 'CONFIRMED'`, and notifies the sender.
- **Reject:** sets status to `REJECTED`, creates an event, marks notification `action_state: 'DONE'` with `action_result: 'REJECTED'`, and notifies the sender.
- **Cancel:** callable by the sender only, and only while status is `PENDING`.

**R6 Outdated Lazy Evaluation:**
`OUTDATED` status is also evaluated lazily whenever a settlement is read.

**R7 Display:**
A ledger whose balance is zero shows "All squared up" and NO Pending, Rejected, or Outdated banners. Only the most recent unresolved settlement per pair is shown. Resubmit is offered only when a debt remains, and it prefills the current valid amount (creates a NEW record linked with `replaced_by_id`; never edits the old one).

**R8 Notifications:**
Notifications are rows in the `notifications` table, written in the same transaction as the event that causes them, read directly from the database. The Notifications page shows actionable items with inline Confirm and Reject buttons. After acting, the item displays its result and stays in the list.

**R9 Refresh:**
In the absence of FCM push: after the receiver acts, the app uses the response and refetches. The sender's phone refreshes on screen open, pull-to-refresh, app resume, and via a poll every 15 seconds while the friend page, settle tab, or notifications page is open (stops polling when closed).
