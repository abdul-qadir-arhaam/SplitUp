# SplitUp: DATABASE.md

> MySQL 8 schema, constraints, indexes and data rules for the SplitUp backend.
> Read with `PRD.md` (rules), `ARCHITECTURE.md` section 4 (backend), `APP_RULES.md` (balance and settlement logic) and `API.md`.
> **For the agent:** implement this schema as versioned Knex migrations (raw SQL is fine). Do not change the schema by hand. If you need a change, add a new migration and update this file in the same change.

---

## 1. Conventions

| Topic | Rule |
|---|---|
| Engine and charset | InnoDB, `utf8mb4`, collation `utf8mb4_0900_ai_ci` |
| MySQL version | 8.0.16 or newer (CHECK constraints are enforced from 8.0.16) |
| IDs | `VARCHAR(64)` (sortable ULID with optional prefix like `ldg_`, `exp_`, `usr_`). Never auto-increment for business entities. Log tables (`settlement_events`, `activity_log`) use `BIGINT UNSIGNED AUTO_INCREMENT`. |
| Money | `BIGINT` **paise**, never `DECIMAL` or `FLOAT`. All money columns end in `_paise`. |
| Time | `DATETIME(3)` in **UTC**. Date-only values use `DATE`. |
| Names | Tables plural `snake_case`; columns `snake_case`. |
| Deletes | **No hard deletes of financial records.** Expenses are soft-deleted (`deleted_at`). Settlements are never deleted. Foreign keys use the default `RESTRICT` (no `CASCADE`). |
| Enums | Stored as `VARCHAR` with a `CHECK ... IN (...)` constraint (easier to migrate than `ENUM`). |
| Balances | **Never stored.** Always computed from `expenses`, `expense_payers`, `expense_splits` and confirmed `settlements`. |
| Immutability | A `CONFIRMED` settlement is never edited. Corrections create new records. |

---

## 2. Entity Overview

```
users ─┬─< friendships (one row per viewer per friend, holds private nickname)
       ├─< user_blocks
       ├─< device_tokens
       └─< ledger_members >─ ledgers (INDIVIDUAL | GROUP | TRIP)
                                 │
                                 ├─< expenses ─┬─< expense_payers
                                 │             ├─< expense_splits
                                 │             └─< disputes
                                 ├─< settlements ─< settlement_events
                                 ├─< activity_log
                                 └─< trip_budget_alerts

offsets (links one group settlement + one individual settlement)
notifications, idempotency_keys, app_config
```

---

## 3. Schema (DDL)

Run in this order. Foreign keys are listed after the tables they reference.

```sql
-- =========================================================
-- 3.1 users
-- =========================================================
CREATE TABLE users (
  id             VARCHAR(64)     NOT NULL,
  firebase_uid   VARCHAR(128) NULL,                -- NULL for placeholders and deleted users
  phone_e164     VARCHAR(16)  NULL,                -- e.g. +919876543210; NULL only when status = DELETED
  name           VARCHAR(100) NOT NULL,            -- profile name (placeholders: name given by the adder)
  email          VARCHAR(254) NULL,
  photo_url      VARCHAR(500) NULL,
  is_placeholder TINYINT(1)   NOT NULL DEFAULT 0,  -- 1 = not yet registered on the app
  status         VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | DELETED
  created_by     VARCHAR(64)     NULL,                -- who first created this placeholder (NULL for real users)
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted_at     DATETIME(3)  NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_phone (phone_e164),
  UNIQUE KEY uq_users_firebase_uid (firebase_uid),
  KEY idx_users_created_by (created_by),
  CONSTRAINT ck_users_status CHECK (status IN ('ACTIVE','DELETED')),
  CONSTRAINT ck_users_phone CHECK (status = 'DELETED' OR phone_e164 IS NOT NULL),
  CONSTRAINT ck_users_placeholder CHECK (is_placeholder = 0 OR firebase_uid IS NULL)
) ENGINE=InnoDB;

ALTER TABLE users
  ADD CONSTRAINT fk_users_created_by FOREIGN KEY (created_by) REFERENCES users(id);

-- =========================================================
-- 3.2 friendships  (two rows per friendship, one per viewer)
-- =========================================================
CREATE TABLE friendships (
  owner_user_id        VARCHAR(64)     NOT NULL,      -- the viewer
  friend_user_id       VARCHAR(64)     NOT NULL,
  individual_ledger_id VARCHAR(64)     NOT NULL,      -- shared by both rows of the pair
  nickname             VARCHAR(100) NULL,          -- PRIVATE: never exposed to friend_user_id
  contact_name         VARCHAR(100) NULL,          -- name saved in the owner's phone contacts (synced from device)
  created_at           DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  removed_at           DATETIME(3)  NULL,          -- set when the owner removes the friend (history is kept)
  PRIMARY KEY (owner_user_id, friend_user_id),
  KEY idx_friendships_friend (friend_user_id),
  KEY idx_friendships_ledger (individual_ledger_id),
  CONSTRAINT ck_friendships_not_self CHECK (owner_user_id <> friend_user_id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.3 user_blocks
-- =========================================================
CREATE TABLE user_blocks (
  blocker_user_id VARCHAR(64)    NOT NULL,
  blocked_user_id VARCHAR(64)    NOT NULL,
  created_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (blocker_user_id, blocked_user_id),
  KEY idx_blocks_blocked (blocked_user_id),
  CONSTRAINT ck_blocks_not_self CHECK (blocker_user_id <> blocked_user_id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.4 ledgers  (INDIVIDUAL | GROUP | TRIP)
-- =========================================================
CREATE TABLE ledgers (
  id             VARCHAR(64)     NOT NULL,
  type           VARCHAR(12)  NOT NULL,            -- INDIVIDUAL | GROUP | TRIP
  name           VARCHAR(100) NULL,                -- NULL for INDIVIDUAL
  photo_url      VARCHAR(500) NULL,
  budget_paise   BIGINT       NULL,                -- TRIP only
  start_date     DATE         NULL,                -- TRIP only (optional)
  end_date       DATE         NULL,                -- TRIP only (optional)
  status         VARCHAR(12)  NOT NULL DEFAULT 'ACTIVE',   -- ACTIVE | COMPLETED | ARCHIVED
  pair_low_user_id  VARCHAR(64)  NULL,                -- INDIVIDUAL only: smaller user id of the pair
  pair_high_user_id VARCHAR(64)  NULL,                -- INDIVIDUAL only: larger user id of the pair
  created_by     VARCHAR(64)     NOT NULL,
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  completed_at   DATETIME(3)  NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ledgers_pair (pair_low_user_id, pair_high_user_id),
  KEY idx_ledgers_type_status (type, status),
  KEY idx_ledgers_created_by (created_by),
  CONSTRAINT ck_ledgers_type   CHECK (type IN ('INDIVIDUAL','GROUP','TRIP')),
  CONSTRAINT ck_ledgers_status CHECK (status IN ('ACTIVE','COMPLETED','ARCHIVED')),
  CONSTRAINT ck_ledgers_budget CHECK (
    (type = 'TRIP' AND budget_paise IS NOT NULL AND budget_paise > 0)
    OR (type <> 'TRIP' AND budget_paise IS NULL)),
  CONSTRAINT ck_ledgers_dates  CHECK (
    (type = 'TRIP') OR (start_date IS NULL AND end_date IS NULL)),
  CONSTRAINT ck_ledgers_date_order CHECK (
    start_date IS NULL OR end_date IS NULL OR start_date <= end_date),
  CONSTRAINT ck_ledgers_pair CHECK (
    (type = 'INDIVIDUAL' AND pair_low_user_id IS NOT NULL AND pair_high_user_id IS NOT NULL
        AND pair_low_user_id < pair_high_user_id)
    OR (type <> 'INDIVIDUAL' AND pair_low_user_id IS NULL AND pair_high_user_id IS NULL)),
  CONSTRAINT ck_ledgers_name CHECK (type = 'INDIVIDUAL' OR name IS NOT NULL)
) ENGINE=InnoDB;

ALTER TABLE ledgers
  ADD CONSTRAINT fk_ledgers_created_by FOREIGN KEY (created_by) REFERENCES users(id),
  ADD CONSTRAINT fk_ledgers_pair_low   FOREIGN KEY (pair_low_user_id)  REFERENCES users(id),
  ADD CONSTRAINT fk_ledgers_pair_high  FOREIGN KEY (pair_high_user_id) REFERENCES users(id);

ALTER TABLE friendships
  ADD CONSTRAINT fk_friendships_owner  FOREIGN KEY (owner_user_id)  REFERENCES users(id),
  ADD CONSTRAINT fk_friendships_friend FOREIGN KEY (friend_user_id) REFERENCES users(id),
  ADD CONSTRAINT fk_friendships_ledger FOREIGN KEY (individual_ledger_id) REFERENCES ledgers(id);

ALTER TABLE user_blocks
  ADD CONSTRAINT fk_blocks_blocker FOREIGN KEY (blocker_user_id) REFERENCES users(id),
  ADD CONSTRAINT fk_blocks_blocked FOREIGN KEY (blocked_user_id) REFERENCES users(id);

-- =========================================================
-- 3.5 ledger_members
-- =========================================================
CREATE TABLE ledger_members (
  ledger_id  VARCHAR(64)    NOT NULL,
  user_id    VARCHAR(64)    NOT NULL,
  role       VARCHAR(10) NOT NULL DEFAULT 'MEMBER',   -- ADMIN | MEMBER  (trip creator = ADMIN)
  added_by   VARCHAR(64)    NULL,                        -- who added this member (used for "confirm on behalf" of placeholders)
  joined_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  left_at    DATETIME(3) NULL,                        -- set when removed or left; row kept for history
  PRIMARY KEY (ledger_id, user_id),
  KEY idx_members_user (user_id, left_at),
  CONSTRAINT ck_members_role CHECK (role IN ('ADMIN','MEMBER')),
  CONSTRAINT fk_members_ledger FOREIGN KEY (ledger_id) REFERENCES ledgers(id),
  CONSTRAINT fk_members_user   FOREIGN KEY (user_id)   REFERENCES users(id),
  CONSTRAINT fk_members_added_by FOREIGN KEY (added_by) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.6 expenses
-- =========================================================
CREATE TABLE expenses (
  id           VARCHAR(64)     NOT NULL,
  ledger_id    VARCHAR(64)     NOT NULL,
  title        VARCHAR(120) NOT NULL,
  total_paise  BIGINT       NOT NULL,
  category     VARCHAR(20)  NOT NULL DEFAULT 'other',
  split_type   VARCHAR(10)  NOT NULL,              -- EQUAL | EXACT | PERCENT | SHARES
  expense_date DATE         NOT NULL,
  note         VARCHAR(500) NULL,
  created_by   VARCHAR(64)     NOT NULL,
  created_at   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted_at   DATETIME(3)  NULL,                  -- soft delete
  deleted_by   VARCHAR(64)     NULL,
  PRIMARY KEY (id),
  KEY idx_expenses_ledger_date (ledger_id, deleted_at, expense_date, id),
  KEY idx_expenses_created_by (created_by),
  CONSTRAINT ck_expenses_total CHECK (total_paise > 0),
  CONSTRAINT ck_expenses_split CHECK (split_type IN ('EQUAL','EXACT','PERCENT','SHARES')),
  CONSTRAINT ck_expenses_category CHECK (category IN
    ('food','travel','stay','fuel','tickets','shopping','groceries','other')),
  CONSTRAINT fk_expenses_ledger  FOREIGN KEY (ledger_id)  REFERENCES ledgers(id),
  CONSTRAINT fk_expenses_creator FOREIGN KEY (created_by) REFERENCES users(id),
  CONSTRAINT fk_expenses_deleter FOREIGN KEY (deleted_by) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.7 expense_payers  (who paid, may be several)
-- =========================================================
CREATE TABLE expense_payers (
  expense_id VARCHAR(64) NOT NULL,
  user_id    VARCHAR(64) NOT NULL,
  paid_paise BIGINT   NOT NULL,
  PRIMARY KEY (expense_id, user_id),
  KEY idx_payers_user (user_id),
  CONSTRAINT ck_payers_paid CHECK (paid_paise > 0),
  CONSTRAINT fk_payers_expense FOREIGN KEY (expense_id) REFERENCES expenses(id),
  CONSTRAINT fk_payers_user    FOREIGN KEY (user_id)    REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.8 expense_splits  (who shared it, and each person's share)
-- =========================================================
CREATE TABLE expense_splits (
  expense_id  VARCHAR(64)    NOT NULL,
  user_id     VARCHAR(64)    NOT NULL,
  included    TINYINT(1)  NOT NULL DEFAULT 1,      -- 0 = "Not there" (owed_paise must be 0)
  owed_paise  BIGINT      NOT NULL DEFAULT 0,      -- final share after rounding (authoritative)
  split_value INT         NULL,                    -- input used: exact amount ignored; percent in basis points
                                                   -- (50.00% = 5000); shares count; NULL for EQUAL
  PRIMARY KEY (expense_id, user_id),
  KEY idx_splits_user (user_id),
  CONSTRAINT ck_splits_owed CHECK (owed_paise >= 0),
  CONSTRAINT ck_splits_excluded CHECK (included = 1 OR owed_paise = 0),
  CONSTRAINT fk_splits_expense FOREIGN KEY (expense_id) REFERENCES expenses(id),
  CONSTRAINT fk_splits_user    FOREIGN KEY (user_id)    REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.9 disputes
-- =========================================================
CREATE TABLE disputes (
  id          VARCHAR(64)    NOT NULL,
  expense_id  VARCHAR(64)    NOT NULL,
  raised_by   VARCHAR(64)    NOT NULL,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_disputes_once (expense_id, raised_by),
  CONSTRAINT fk_disputes_expense FOREIGN KEY (expense_id) REFERENCES expenses(id),
  CONSTRAINT fk_disputes_user    FOREIGN KEY (raised_by)  REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.10 offsets  (links one GROUP settlement and one INDIVIDUAL settlement)
-- =========================================================
CREATE TABLE offsets (
  id                    VARCHAR(64)    NOT NULL,
  group_ledger_id       VARCHAR(64)    NOT NULL,
  individual_ledger_id  VARCHAR(64)    NOT NULL,
  from_user_id          VARCHAR(64)    NOT NULL,   -- the person who owes in the GROUP and initiates
  to_user_id            VARCHAR(64)    NOT NULL,   -- the receiver in the GROUP (confirms)
  amount_paise          BIGINT      NOT NULL,
  status                VARCHAR(10) NOT NULL DEFAULT 'PENDING',
  created_by            VARCHAR(64)    NOT NULL,
  created_at            DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  responded_at          DATETIME(3) NULL,
  PRIMARY KEY (id),
  KEY idx_offsets_group (group_ledger_id, status),
  KEY idx_offsets_to (to_user_id, status),
  CONSTRAINT ck_offsets_amount CHECK (amount_paise > 0),
  CONSTRAINT ck_offsets_status CHECK (status IN ('PENDING','CONFIRMED','REJECTED','OUTDATED','CANCELLED')),
  CONSTRAINT ck_offsets_users  CHECK (from_user_id <> to_user_id),
  CONSTRAINT fk_offsets_group FOREIGN KEY (group_ledger_id)      REFERENCES ledgers(id),
  CONSTRAINT fk_offsets_indiv FOREIGN KEY (individual_ledger_id) REFERENCES ledgers(id),
  CONSTRAINT fk_offsets_from  FOREIGN KEY (from_user_id)         REFERENCES users(id),
  CONSTRAINT fk_offsets_to    FOREIGN KEY (to_user_id)           REFERENCES users(id),
  CONSTRAINT fk_offsets_creator FOREIGN KEY (created_by)         REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.11 settlements
-- =========================================================
CREATE TABLE settlements (
  id                  VARCHAR(64)    NOT NULL,
  ledger_id           VARCHAR(64)    NOT NULL,
  from_user_id        VARCHAR(64)    NOT NULL,       -- the SENDER of money (creates the request)
  to_user_id          VARCHAR(64)    NOT NULL,       -- the RECEIVER (confirms or rejects)
  amount_paise        BIGINT      NOT NULL,
  method              VARCHAR(10) NOT NULL DEFAULT 'CASH',   -- CASH | UPI | OFFSET | OTHER
  status              VARCHAR(10) NOT NULL DEFAULT 'PENDING',-- PENDING | CONFIRMED | REJECTED | OUTDATED | CANCELLED
  offset_id           VARCHAR(64)    NULL,           -- set for both entries of an offset
  replaced_by_id      VARCHAR(64)    NULL,           -- set on the old record when resubmitted
  created_by          VARCHAR(64)    NOT NULL,       -- normally = from_user_id
  responded_by        VARCHAR(64)    NULL,           -- who confirmed/rejected (receiver, or the person acting on behalf)
  confirmed_on_behalf TINYINT(1)  NOT NULL DEFAULT 0,  -- 1 = self-confirmed (unverified) for a placeholder receiver
  reminder_count      TINYINT     NOT NULL DEFAULT 0,
  last_reminded_at    DATETIME(3) NULL,
  created_at          DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  responded_at        DATETIME(3) NULL,
  PRIMARY KEY (id),
  KEY idx_settlements_ledger (ledger_id, status),
  KEY idx_settlements_to (to_user_id, status),
  KEY idx_settlements_from (from_user_id, status),
  KEY idx_settlements_offset (offset_id),
  CONSTRAINT ck_settlements_amount CHECK (amount_paise > 0),
  CONSTRAINT ck_settlements_users  CHECK (from_user_id <> to_user_id),
  CONSTRAINT ck_settlements_method CHECK (method IN ('CASH','UPI','OFFSET','OTHER')),
  CONSTRAINT ck_settlements_status CHECK (status IN ('PENDING','CONFIRMED','REJECTED','OUTDATED','CANCELLED')),
  CONSTRAINT ck_settlements_offset CHECK ((method = 'OFFSET') = (offset_id IS NOT NULL)),
  CONSTRAINT fk_settlements_ledger FOREIGN KEY (ledger_id)      REFERENCES ledgers(id),
  CONSTRAINT fk_settlements_from   FOREIGN KEY (from_user_id)   REFERENCES users(id),
  CONSTRAINT fk_settlements_to     FOREIGN KEY (to_user_id)     REFERENCES users(id),
  CONSTRAINT fk_settlements_offset FOREIGN KEY (offset_id)      REFERENCES offsets(id),
  CONSTRAINT fk_settlements_replaced FOREIGN KEY (replaced_by_id) REFERENCES settlements(id),
  CONSTRAINT fk_settlements_creator FOREIGN KEY (created_by)    REFERENCES users(id),
  CONSTRAINT fk_settlements_responder FOREIGN KEY (responded_by) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.12 settlement_events  (audit trail of every status change)
-- =========================================================
CREATE TABLE settlement_events (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  settlement_id  VARCHAR(64)    NOT NULL,
  status         VARCHAR(10) NOT NULL,
  actor_user_id  VARCHAR(64)    NOT NULL,
  created_at     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_sevents_settlement (settlement_id, id),
  CONSTRAINT fk_sevents_settlement FOREIGN KEY (settlement_id) REFERENCES settlements(id),
  CONSTRAINT fk_sevents_actor      FOREIGN KEY (actor_user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.13 activity_log  (visible history for groups, trips, individual ledgers)
-- =========================================================
CREATE TABLE activity_log (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ledger_id      VARCHAR(64)     NOT NULL,
  actor_user_id  VARCHAR(64)     NOT NULL,
  action         VARCHAR(40)  NOT NULL,   -- EXPENSE_CREATED, EXPENSE_EDITED, EXPENSE_DELETED, EXPENSE_DISPUTED,
                                          -- BUDGET_CHANGED, MEMBER_ADDED, MEMBER_REMOVED, MEMBER_LEFT,
                                          -- LEDGER_RENAMED, LEDGER_COMPLETED, SETTLEMENT_<STATUS>, ...
  entity_type    VARCHAR(20)  NOT NULL,   -- expense | settlement | ledger | member
  entity_id      VARCHAR(64)     NULL,
  payload        JSON         NULL,       -- before/after values, e.g. {"from_paise":120000,"to_paise":100000}
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_activity_ledger (ledger_id, id),
  KEY idx_activity_entity (entity_type, entity_id),
  CONSTRAINT fk_activity_ledger FOREIGN KEY (ledger_id)     REFERENCES ledgers(id),
  CONSTRAINT fk_activity_actor  FOREIGN KEY (actor_user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.14 trip_budget_alerts  (send each threshold only once per trip)
-- =========================================================
CREATE TABLE trip_budget_alerts (
  ledger_id  VARCHAR(64)    NOT NULL,
  threshold  SMALLINT    NOT NULL,            -- 80 or 100
  sent_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (ledger_id, threshold),
  CONSTRAINT ck_alerts_threshold CHECK (threshold IN (80, 100)),
  CONSTRAINT fk_alerts_ledger FOREIGN KEY (ledger_id) REFERENCES ledgers(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.15 notifications  (in-app feed; FCM push is sent in addition)
-- =========================================================
CREATE TABLE notifications (
  id            VARCHAR(64)    NOT NULL,
  user_id       VARCHAR(64)    NOT NULL,          -- recipient
  type          VARCHAR(40) NOT NULL,          -- FRIEND_ADDED, FRIEND_JOINED, ADDED_TO_GROUP, ADDED_TO_TRIP,
                                               -- SETTLEMENT_REQUESTED, SETTLEMENT_CONFIRMED, SETTLEMENT_REJECTED,
                                               -- SETTLEMENT_OUTDATED, OFFSET_REQUESTED, OFFSET_RESULT,
                                               -- EXPENSE_DISPUTED, BUDGET_WARNING, MEMBER_REMOVED, ...
  payload       JSON        NOT NULL,          -- ids and display-safe values only (no private nicknames)
  action_state  VARCHAR(10) NULL,              -- NULL for informational; OPEN | DONE | EXPIRED for actionable
  action_result VARCHAR(20) NULL,              -- e.g. CONFIRMED, REJECTED, REMOVED, BLOCKED
  read_at       DATETIME(3) NULL,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_notifications_user (user_id, created_at, id),
  KEY idx_notifications_unread (user_id, read_at),
  CONSTRAINT ck_notifications_state CHECK (action_state IS NULL OR action_state IN ('OPEN','DONE','EXPIRED')),
  CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.16 device_tokens  (FCM)
-- =========================================================
CREATE TABLE device_tokens (
  id           VARCHAR(64)     NOT NULL,
  user_id      VARCHAR(64)     NOT NULL,
  fcm_token    VARCHAR(512) NOT NULL,
  platform     VARCHAR(10)  NOT NULL DEFAULT 'android',
  created_at   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_seen_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_device_token (fcm_token(191)),
  KEY idx_device_user (user_id),
  CONSTRAINT fk_device_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.17 idempotency_keys
-- =========================================================
CREATE TABLE idempotency_keys (
  user_id         VARCHAR(64)     NOT NULL,
  key_value       VARCHAR(64)  NOT NULL,       -- client-generated UUID
  request_hash    CHAR(64)     NOT NULL,       -- SHA-256 of method + path + body; same key with different body = error
  resource_type   VARCHAR(20)  NULL,
  resource_id     VARCHAR(64)     NULL,
  response_status SMALLINT     NULL,
  response_body   JSON         NULL,
  created_at      DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at      DATETIME(3)  NOT NULL,       -- created_at + 24 hours
  PRIMARY KEY (user_id, key_value),
  KEY idx_idem_expires (expires_at),
  CONSTRAINT fk_idem_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- =========================================================
-- 3.18 app_config  (single row; drives the in-app update check)
-- =========================================================
CREATE TABLE app_config (
  id                        TINYINT      NOT NULL DEFAULT 1,
  latest_version_code       INT          NOT NULL,
  latest_version_name       VARCHAR(20)  NOT NULL,
  min_supported_version_code INT         NOT NULL,
  download_page_url         VARCHAR(300) NOT NULL,
  updated_at                DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  CONSTRAINT ck_app_config_single CHECK (id = 1)
) ENGINE=InnoDB;
```

---

## 4. Rules the Schema Cannot Enforce (enforce in code and test)

SQL constraints cover shape and per-row checks. These cross-row rules **must be enforced in the service layer inside the same transaction, and have automated tests**:

| # | Rule | Where |
|---|---|---|
| 1 | `SUM(expense_payers.paid_paise) = expenses.total_paise` | Expense create/edit |
| 2 | `SUM(expense_splits.owed_paise) = expenses.total_paise` (excluded members have 0) | Expense create/edit |
| 3 | Every payer and split user is a **current member** of the expense's ledger; an excluded ("Not there") member is **not** a payer | Expense create/edit |
| 4 | EXACT: owed amounts sum to total. PERCENT: `split_value` basis points sum to 10000. SHARES: shares are positive integers. | Expense create/edit |
| 5 | Settlement `from_user_id` and `to_user_id` are both members of `ledger_id` | Settlement create |
| 6 | Settlement amount passes the validity rule in `APP_RULES.md` | Settlement create, view, confirm |
| 7 | Only the receiver (or the placeholder's `added_by` acting on behalf) may confirm or reject; only the sender may cancel while `PENDING` | Settlement endpoints |
| 8 | An `OFFSET` pairs exactly **two** settlements: one in the group ledger (`from` = group debtor, `to` = group creditor) and one in the individual ledger in the **opposite** direction (`from` = original creditor, `to` = original debtor), same `amount_paise`, same `offset_id`. The offset's status and both settlement statuses always change together, in one transaction. | Offset endpoints |
| 9 | Trips never take part in offsets: an offset's group ledger must be `type = 'GROUP'` and the other `type = 'INDIVIDUAL'` | Offset create |
| 10 | Ledger `type` never changes after creation | Ledger update |
| 11 | A member with unsettled balance cannot be removed, leave, or be unfriended (see section 6.4) | Member and friend endpoints |
| 12 | Only the trip creator (`role = ADMIN`) changes the budget, and each change is written to `activity_log` | Trip update |
| 13 | A confirmed settlement is never updated or deleted | All |
| 14 | Individual ledger has exactly two members, the pair stored in `pair_low_user_id` / `pair_high_user_id` | Friend add |

---

## 5. Placeholder Users

- A placeholder is a `users` row with `is_placeholder = 1`, a `phone_e164`, a `name` (given by the adder), and no `firebase_uid`.
- **One placeholder per phone number** (unique index). If two people add the same unregistered number, they share one placeholder.
- The **"confirm on behalf"** person for a placeholder in a given ledger is `ledger_members.added_by` for that placeholder in **that ledger** (for an individual ledger, this is simply the other member). Do not use `users.created_by` for this. It only records who first created the row.
- Placeholders never appear in contact lookups as "is_user".

### 5.1 Merge procedure (placeholder becomes a real user)

Triggered when a user verifies a phone number and a placeholder with that number exists. Run in **one transaction**:

1. Lock the placeholder row (`SELECT ... FOR UPDATE`) and the real user row.
2. Re-point every reference from `placeholder.id` to `real.id`, in this order:
   - `ledger_members`: if the real user already has a row in that ledger, keep the real row and drop the placeholder's; otherwise update `user_id`. Do the same for `added_by` (plain update).
   - `ledgers.pair_low_user_id` / `pair_high_user_id` for individual ledgers: update, then **re-order** so `pair_low < pair_high` still holds. If an individual ledger between the same two people already exists (unusual), keep the older ledger and move the newer one's expenses and settlements into it, then mark the newer one `ARCHIVED`.
   - `friendships`: update `owner_user_id` and `friend_user_id`; on a primary-key conflict keep the row with more data (nickname preferred) and drop the other.
   - `expense_payers` and `expense_splits`: update `user_id`; on conflict (both in the same expense) add the amounts together.
   - `expenses.created_by`, `expenses.deleted_by`, `ledgers.created_by`.
   - `settlements.from_user_id`, `to_user_id`, `created_by`, `responded_by`; `offsets.from_user_id`, `to_user_id`, `created_by`; `settlement_events.actor_user_id`.
   - `activity_log.actor_user_id`, `disputes.raised_by`, `notifications.user_id`, `user_blocks` (both columns), `users.created_by`.
3. Set the real user's `name` only if empty (the real profile name wins). Do **not** overwrite nicknames or contact names.
4. Delete the placeholder row (the only hard delete of a user row allowed, and only here).
5. Write notifications for the people who added the placeholder: `FRIEND_JOINED`.
6. Return a summary: count of expenses and total amount now visible to the new user.

After the merge, the zero-sum check (section 7.3) must still hold for every affected ledger. Run it in the merge test.

---

## 6. Core Queries

### 6.1 Net balance per member in one ledger

`net = paid - owed + settlements SENT - settlements RECEIVED` (confirmed only). **Positive = the member is owed money.**

```sql
SELECT m.user_id,
       COALESCE(p.paid, 0) - COALESCE(s.owed, 0)
         + COALESCE(ss.sent, 0) - COALESCE(sr.received, 0) AS net_paise
FROM ledger_members m
LEFT JOIN (
    SELECT ep.user_id, SUM(ep.paid_paise) AS paid
    FROM expense_payers ep
    JOIN expenses e ON e.id = ep.expense_id
    WHERE e.ledger_id = :ledger AND e.deleted_at IS NULL
    GROUP BY ep.user_id) p  ON p.user_id  = m.user_id
LEFT JOIN (
    SELECT es.user_id, SUM(es.owed_paise) AS owed
    FROM expense_splits es
    JOIN expenses e ON e.id = es.expense_id
    WHERE e.ledger_id = :ledger AND e.deleted_at IS NULL
    GROUP BY es.user_id) s  ON s.user_id  = m.user_id
LEFT JOIN (
    SELECT from_user_id AS user_id, SUM(amount_paise) AS sent
    FROM settlements
    WHERE ledger_id = :ledger AND status = 'CONFIRMED'
    GROUP BY from_user_id) ss ON ss.user_id = m.user_id
LEFT JOIN (
    SELECT to_user_id AS user_id, SUM(amount_paise) AS received
    FROM settlements
    WHERE ledger_id = :ledger AND status = 'CONFIRMED'
    GROUP BY to_user_id) sr ON sr.user_id = m.user_id
WHERE m.ledger_id = :ledger;
```

Sign check: A owes Rs 200 (net -200). A sends B a confirmed Rs 200 settlement. A's net becomes -200 + 200 = 0. B's net was +200, now +200 - 200 = 0.

Members who left (`left_at` not null) must still be included if they have history. Do not filter on `left_at` for balance math.

> **Important:** the pairwise ("Actual") debts and the simplified plan are computed in application code (the pure `balances` module) from the same rows. Do not try to compute them in SQL.

### 6.2 Balances for the profile and home totals
Sum the positive nets and the negative nets of the current user across the ledgers defined in `PRD.md` (profile totals) and across individual ledgers for the Home summary. Computed per request from the rows above; optionally cached in the app. Never stored.

### 6.3 Pending settlements awaiting my response

```sql
SELECT * FROM settlements
WHERE to_user_id = :me AND status = 'PENDING'
ORDER BY created_at;
```

### 6.4 Unsettled-balance guard (remove member, leave group, unfriend)

A member has unsettled balance in a ledger if their net (section 6.1) is not 0 **or** they have a `PENDING` settlement as sender or receiver in that ledger. The operation returns `UNSETTLED_BALANCE` if either is true.

### 6.5 Expenses list (cursor pagination)

```sql
SELECT * FROM expenses
WHERE ledger_id = :ledger AND deleted_at IS NULL
  AND (expense_date, id) < (:cursor_date, :cursor_id)
ORDER BY expense_date DESC, id DESC
LIMIT :limit;
```

### 6.6 Budget progress (trip)

```sql
SELECT l.budget_paise,
       COALESCE(SUM(e.total_paise), 0) AS spent_paise
FROM ledgers l
LEFT JOIN expenses e ON e.ledger_id = l.id AND e.deleted_at IS NULL
WHERE l.id = :ledger
GROUP BY l.id, l.budget_paise;
```

Budget level is derived from `spent_paise / budget_paise` using the thresholds in `PRD.md` TRP-5. When an expense is saved, compare the percentage before and after and insert into `trip_budget_alerts` (ignore if the row exists) to send each threshold once.

### 6.7 Spending by category and by day (dashboards)

```sql
SELECT category, SUM(total_paise) AS total_paise
FROM expenses WHERE ledger_id = :ledger AND deleted_at IS NULL
GROUP BY category;

SELECT expense_date, SUM(total_paise) AS total_paise
FROM expenses WHERE ledger_id = :ledger AND deleted_at IS NULL
GROUP BY expense_date ORDER BY expense_date;
```

---

## 7. Transactions, Locking and Integrity

### 7.1 Isolation and locking
- Use `REPEATABLE READ` (the MySQL default) and take explicit locks where a decision depends on current data.
- **Settlement confirm / reject / resubmit:** `SELECT ... FROM settlements WHERE id = ? FOR UPDATE`, then lock the ledger's `ledger_members` rows (`FOR UPDATE`) before recomputing balances, so a concurrent expense edit or second confirm cannot slip in.
- **Offsets:** lock the offset row, both settlement rows, and the member rows of **both** ledgers, always in a fixed order (group ledger first, then individual ledger; rows ordered by id) to avoid deadlocks.
- **Expense create/edit/delete:** lock the expense row (edit/delete) and write the activity log in the same transaction.
- Retry a transaction automatically on deadlock (error 1213) up to 3 times.

### 7.2 Transactions required
Create expense (with payers, splits, activity), edit expense, delete expense, create settlement, confirm/reject/cancel settlement, resubmit, create/confirm/reject offset, placeholder merge, add friend (user lookup/placeholder, friendship rows, individual ledger, membership, notification), create group/trip with members, remove/leave member.

### 7.3 Zero-sum invariant
For every ledger, `SUM(net_paise)` over all members **must equal 0**. Provide a reusable function and a scheduled check:

```sql
-- Returns ledgers that violate the invariant (must return zero rows)
SELECT ledger_id FROM (
  SELECT ledger_id, SUM(net_paise) AS total FROM ledger_net_view GROUP BY ledger_id
) t WHERE total <> 0;
```

`ledger_net_view` is the query in 6.1 generalized over all ledgers (create it as a view, or run the check in application code). Run this check in integration tests after every scenario and daily in production, logging an alert if any row is returned.

---

## 8. Indexing Notes

- All foreign key columns used for joins are indexed (see DDL). Re-check with `EXPLAIN` on the queries in section 6 against seed data.
- `idx_expenses_ledger_date` supports the expense list, dashboards and balance sums.
- `idx_settlements_*` support "my pending requests", the ledger settle tab and reminders.
- `idx_notifications_user` supports the feed; `idx_notifications_unread` supports the badge count.
- Do not add indexes speculatively. Add them when a measured query needs one, in a new migration.

---

## 9. Account Deletion (anonymization)

On account deletion, in one transaction:
1. `users`: set `name = 'Deleted user'`, `email = NULL`, `photo_url = NULL`, `phone_e164 = NULL`, `firebase_uid = NULL`, `status = 'DELETED'`, `deleted_at = now`.
2. Delete this user's `device_tokens`, `notifications`, `friendships` where they are owner, and `user_blocks` rows. Keep rows where they are the **friend**, so other people's history stays intact (display name resolves to "Deleted user").
3. Keep all `ledger_members`, `expense_payers`, `expense_splits`, `settlements` and `activity_log` rows. Others' balances must not change.
4. Freeing the phone number lets the person sign up again later as a **new** user. Their old history stays with "Deleted user".
5. Pending settlements involving the deleted user are set to `CANCELLED` with an event.

---

## 10. Migrations

- Tool: Knex migrations in `backend/src/db/migrations`, files named `YYYYMMDDHHmm_description.js` (or `.ts`), each with `up` and `down`.
- Suggested initial set (in order): `001_users`, `002_ledgers_and_friendships`, `003_ledger_members`, `004_expenses_and_splits`, `005_offsets_and_settlements`, `006_activity_notifications_devices`, `007_idempotency_and_config`, `008_views`.
- Never edit a migration after it has been applied to any shared database. Add a new one.
- The app refuses to start if pending migrations exist in `prod` (migrations are run as a deploy step).

---

## 11. Seed and Test Data

Provide `db/seeds/dev.ts` (development only, never run in prod) with:
- 6 realistic Indian-named users (some placeholders)
- 4 friendships with individual ledgers
- 1 group of 5 with 12 expenses (one with an excluded member, one with two payers)
- 1 trip of 4 with a budget and expenses reaching about 64% of the budget
- Settlements in each status: pending, confirmed, rejected, outdated
- One offset pair

Shared JSON test vectors live in `shared/test-vectors/` (not in the database). Integration tests build their own data per test and use a clean database each run.

---

## 12. Backup, Retention and Operations

- **Backups:** daily automated full backup, plus binary logging for point-in-time recovery if the host supports it. Keep at least 14 days. **Test a restore** before launch and after any host change.
- **Retention:** financial records are kept indefinitely. Purge only: expired `idempotency_keys` (after 24 hours), invalid `device_tokens`, and `notifications` older than 12 months (informational ones only; keep actionable ones with settlement links).
- **Time zone:** the database connection time zone is set to UTC. The app converts to local time for display.
- **Connections:** use a pool (for example 10 connections for a friends-scale app). Use `utf8mb4` on the connection.
- **Credentials:** the app database user has only `SELECT, INSERT, UPDATE, DELETE` on the application schema (no `DROP`, `ALTER`, `GRANT`). Migrations run with a separate, more privileged user during deploys.
- **Monitoring:** alert on slow queries (over 500 ms), connection saturation, disk usage and any zero-sum violation.

---

## 13. Reserved for Later (not built in v1)

**`pending_operations`** (Phase 7, offline sync). Sketch only, do not create now:

```
pending_operations (device-side SQLite, not MySQL):
  id, idempotency_key, method, path, body, created_at, attempts, last_error, status
```

The server already supports safe retries through `idempotency_keys`.

Other future tables: `receipts`, `recurring_expenses`, `upi_handles`. Not part of v1.