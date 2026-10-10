import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  // 1. users
  await knex.schema.createTable('users', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.string('firebase_uid', 128).nullable().unique();
    table.string('phone_e164', 16).nullable().unique();
    table.string('name', 100).notNullable();
    table.string('email', 254).nullable();
    table.string('photo_url', 500).nullable();
    table.boolean('is_placeholder').notNullable().defaultTo(false);
    table.string('status', 10).notNullable().defaultTo('ACTIVE');
    table.specificType('created_by', 'CHAR(26)').nullable();
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('deleted_at', { precision: 3 }).nullable();
  });

  // 2. ledgers
  await knex.schema.createTable('ledgers', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.string('type', 12).notNullable(); // INDIVIDUAL | GROUP | TRIP
    table.string('name', 100).nullable();
    table.string('photo_url', 500).nullable();
    table.bigInteger('budget_paise').nullable();
    table.date('start_date').nullable();
    table.date('end_date').nullable();
    table.string('status', 12).notNullable().defaultTo('ACTIVE');
    table.specificType('pair_low_user_id', 'CHAR(26)').nullable().references('id').inTable('users');
    table.specificType('pair_high_user_id', 'CHAR(26)').nullable().references('id').inTable('users');
    table.specificType('created_by', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('completed_at', { precision: 3 }).nullable();

    table.unique(['pair_low_user_id', 'pair_high_user_id'], { indexName: 'uq_ledgers_pair' });
    table.index(['type', 'status'], 'idx_ledgers_type_status');
  });

  // 3. friendships
  await knex.schema.createTable('friendships', (table) => {
    table.specificType('owner_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.specificType('friend_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.specificType('individual_ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.string('nickname', 100).nullable();
    table.string('contact_name', 100).nullable();
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('removed_at', { precision: 3 }).nullable();

    table.primary(['owner_user_id', 'friend_user_id']);
  });

  // 4. user_blocks
  await knex.schema.createTable('user_blocks', (table) => {
    table.specificType('blocker_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.specificType('blocked_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    table.primary(['blocker_user_id', 'blocked_user_id']);
  });

  // 5. ledger_members
  await knex.schema.createTable('ledger_members', (table) => {
    table.specificType('ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.specificType('user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.string('role', 10).notNullable().defaultTo('MEMBER');
    table.specificType('added_by', 'CHAR(26)').nullable().references('id').inTable('users');
    table.datetime('joined_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('left_at', { precision: 3 }).nullable();

    table.primary(['ledger_id', 'user_id']);
    table.index(['user_id', 'left_at'], 'idx_members_user');
  });

  // 6. expenses
  await knex.schema.createTable('expenses', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.specificType('ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.string('title', 120).notNullable();
    table.bigInteger('total_paise').notNullable();
    table.string('category', 20).notNullable().defaultTo('other');
    table.string('split_type', 10).notNullable(); // EQUAL | EXACT | PERCENT | SHARES
    table.date('expense_date').notNullable();
    table.string('note', 500).nullable();
    table.specificType('created_by', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('deleted_at', { precision: 3 }).nullable();
    table.specificType('deleted_by', 'CHAR(26)').nullable().references('id').inTable('users');

    table.index(['ledger_id', 'deleted_at', 'expense_date', 'id'], 'idx_expenses_ledger_date');
  });

  // 7. expense_payers
  await knex.schema.createTable('expense_payers', (table) => {
    table.specificType('expense_id', 'CHAR(26)').notNullable().references('id').inTable('expenses');
    table.specificType('user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.bigInteger('paid_paise').notNullable();

    table.primary(['expense_id', 'user_id']);
  });

  // 8. expense_splits
  await knex.schema.createTable('expense_splits', (table) => {
    table.specificType('expense_id', 'CHAR(26)').notNullable().references('id').inTable('expenses');
    table.specificType('user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.boolean('included').notNullable().defaultTo(true);
    table.bigInteger('owed_paise').notNullable().defaultTo(0);
    table.integer('split_value').nullable();

    table.primary(['expense_id', 'user_id']);
  });

  // 9. disputes
  await knex.schema.createTable('disputes', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.specificType('expense_id', 'CHAR(26)').notNullable().references('id').inTable('expenses');
    table.specificType('raised_by', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    table.unique(['expense_id', 'raised_by'], { indexName: 'uq_disputes_once' });
  });

  // 10. offsets
  await knex.schema.createTable('offsets', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.specificType('group_ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.specificType('individual_ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.specificType('from_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.specificType('to_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.bigInteger('amount_paise').notNullable();
    table.string('status', 10).notNullable().defaultTo('PENDING');
    table.specificType('created_by', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('responded_at', { precision: 3 }).nullable();
  });

  // 11. settlements
  await knex.schema.createTable('settlements', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.specificType('ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.specificType('from_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.specificType('to_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.bigInteger('amount_paise').notNullable();
    table.string('method', 10).notNullable().defaultTo('CASH'); // CASH | UPI | OFFSET | OTHER
    table.string('status', 10).notNullable().defaultTo('PENDING'); // PENDING | CONFIRMED | REJECTED | OUTDATED | CANCELLED
    table.specificType('offset_id', 'CHAR(26)').nullable().references('id').inTable('offsets');
    table.specificType('replaced_by_id', 'CHAR(26)').nullable();
    table.specificType('created_by', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.specificType('responded_by', 'CHAR(26)').nullable().references('id').inTable('users');
    table.boolean('confirmed_on_behalf').notNullable().defaultTo(false);
    table.integer('reminder_count').notNullable().defaultTo(0);
    table.datetime('last_reminded_at', { precision: 3 }).nullable();
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('responded_at', { precision: 3 }).nullable();

    table.index(['ledger_id', 'status'], 'idx_settlements_ledger');
    table.index(['to_user_id', 'status'], 'idx_settlements_to');
    table.index(['from_user_id', 'status'], 'idx_settlements_from');
  });

  // 12. settlement_events
  await knex.schema.createTable('settlement_events', (table) => {
    table.bigIncrements('id').primary();
    table.specificType('settlement_id', 'CHAR(26)').notNullable().references('id').inTable('settlements');
    table.string('status', 10).notNullable();
    table.specificType('actor_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  });

  // 13. activity_log
  await knex.schema.createTable('activity_log', (table) => {
    table.bigIncrements('id').primary();
    table.specificType('ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.specificType('actor_user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.string('action', 40).notNullable();
    table.string('entity_type', 20).notNullable();
    table.specificType('entity_id', 'CHAR(26)').nullable();
    table.json('payload').nullable();
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  });

  // 14. trip_budget_alerts
  await knex.schema.createTable('trip_budget_alerts', (table) => {
    table.specificType('ledger_id', 'CHAR(26)').notNullable().references('id').inTable('ledgers');
    table.smallint('threshold').notNullable(); // 80 or 100
    table.datetime('sent_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    table.primary(['ledger_id', 'threshold']);
  });

  // 15. notifications
  await knex.schema.createTable('notifications', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.specificType('user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.string('type', 40).notNullable();
    table.json('payload').notNullable();
    table.string('action_state', 10).nullable();
    table.string('action_result', 20).nullable();
    table.datetime('read_at', { precision: 3 }).nullable();
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    table.index(['user_id', 'created_at', 'id'], 'idx_notifications_user');
  });

  // 16. device_tokens
  await knex.schema.createTable('device_tokens', (table) => {
    table.specificType('id', 'CHAR(26)').primary();
    table.specificType('user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.string('fcm_token', 512).notNullable();
    table.string('platform', 10).notNullable().defaultTo('android');
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('last_seen_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));

    table.unique(['fcm_token'], { indexName: 'uq_device_token' });
  });

  // 17. idempotency_keys
  await knex.schema.createTable('idempotency_keys', (table) => {
    table.specificType('user_id', 'CHAR(26)').notNullable().references('id').inTable('users');
    table.string('key_value', 64).notNullable();
    table.specificType('request_hash', 'CHAR(64)').notNullable();
    table.string('resource_type', 20).nullable();
    table.specificType('resource_id', 'CHAR(26)').nullable();
    table.smallint('response_status').nullable();
    table.json('response_body').nullable();
    table.datetime('created_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
    table.datetime('expires_at', { precision: 3 }).notNullable();

    table.primary(['user_id', 'key_value']);
  });

  // 18. app_config
  await knex.schema.createTable('app_config', (table) => {
    table.tinyint('id').notNullable().defaultTo(1).primary();
    table.integer('latest_version_code').notNullable();
    table.string('latest_version_name', 20).notNullable();
    table.integer('min_supported_version_code').notNullable();
    table.string('download_page_url', 300).notNullable();
    table.datetime('updated_at', { precision: 3 }).notNullable().defaultTo(knex.fn.now(3));
  });
}

export async function down(knex: Knex): Promise<void> {
  await knex.schema.dropTableIfExists('app_config');
  await knex.schema.dropTableIfExists('idempotency_keys');
  await knex.schema.dropTableIfExists('device_tokens');
  await knex.schema.dropTableIfExists('notifications');
  await knex.schema.dropTableIfExists('trip_budget_alerts');
  await knex.schema.dropTableIfExists('activity_log');
  await knex.schema.dropTableIfExists('settlement_events');
  await knex.schema.dropTableIfExists('settlements');
  await knex.schema.dropTableIfExists('offsets');
  await knex.schema.dropTableIfExists('disputes');
  await knex.schema.dropTableIfExists('expense_splits');
  await knex.schema.dropTableIfExists('expense_payers');
  await knex.schema.dropTableIfExists('expenses');
  await knex.schema.dropTableIfExists('ledger_members');
  await knex.schema.dropTableIfExists('user_blocks');
  await knex.schema.dropTableIfExists('friendships');
  await knex.schema.dropTableIfExists('ledgers');
  await knex.schema.dropTableIfExists('users');
}
