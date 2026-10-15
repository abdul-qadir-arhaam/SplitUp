import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  await knex.raw('SET FOREIGN_KEY_CHECKS = 0');

  const fks = [
    ['ledgers', 'ledgers_pair_low_user_id_foreign'],
    ['ledgers', 'ledgers_pair_high_user_id_foreign'],
    ['ledgers', 'ledgers_created_by_foreign'],
    ['friendships', 'friendships_owner_user_id_foreign'],
    ['friendships', 'friendships_friend_user_id_foreign'],
    ['friendships', 'friendships_individual_ledger_id_foreign'],
    ['user_blocks', 'user_blocks_blocker_user_id_foreign'],
    ['user_blocks', 'user_blocks_blocked_user_id_foreign'],
    ['ledger_members', 'ledger_members_ledger_id_foreign'],
    ['ledger_members', 'ledger_members_user_id_foreign'],
    ['ledger_members', 'ledger_members_added_by_foreign'],
    ['expenses', 'expenses_ledger_id_foreign'],
    ['expenses', 'expenses_created_by_foreign'],
    ['expenses', 'expenses_deleted_by_foreign'],
    ['expense_payers', 'expense_payers_expense_id_foreign'],
    ['expense_payers', 'expense_payers_user_id_foreign'],
    ['expense_splits', 'expense_splits_expense_id_foreign'],
    ['expense_splits', 'expense_splits_user_id_foreign'],
    ['disputes', 'disputes_expense_id_foreign'],
    ['disputes', 'disputes_raised_by_foreign'],
    ['offsets', 'offsets_group_ledger_id_foreign'],
    ['offsets', 'offsets_individual_ledger_id_foreign'],
    ['offsets', 'offsets_from_user_id_foreign'],
    ['offsets', 'offsets_to_user_id_foreign'],
    ['offsets', 'offsets_created_by_foreign'],
    ['settlements', 'settlements_ledger_id_foreign'],
    ['settlements', 'settlements_from_user_id_foreign'],
    ['settlements', 'settlements_to_user_id_foreign'],
    ['settlements', 'settlements_offset_id_foreign'],
    ['settlements', 'settlements_created_by_foreign'],
    ['settlements', 'settlements_responded_by_foreign'],
    ['settlement_events', 'settlement_events_settlement_id_foreign'],
    ['settlement_events', 'settlement_events_actor_user_id_foreign'],
    ['activity_log', 'activity_log_ledger_id_foreign'],
    ['activity_log', 'activity_log_actor_user_id_foreign'],
    ['trip_budget_alerts', 'trip_budget_alerts_ledger_id_foreign'],
    ['notifications', 'notifications_user_id_foreign'],
    ['device_tokens', 'device_tokens_user_id_foreign'],
    ['idempotency_keys', 'idempotency_keys_user_id_foreign'],
  ];

  for (const [tbl, fk] of fks) {
    try {
      await knex.raw(`ALTER TABLE \`${tbl}\` DROP FOREIGN KEY \`${fk}\``);
    } catch {
      // Ignore if FK does not exist
    }
  }

  const columnModifications = [
    'ALTER TABLE `users` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `users` MODIFY `created_by` VARCHAR(64) NULL',
    'ALTER TABLE `ledgers` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `ledgers` MODIFY `pair_low_user_id` VARCHAR(64) NULL',
    'ALTER TABLE `ledgers` MODIFY `pair_high_user_id` VARCHAR(64) NULL',
    'ALTER TABLE `ledgers` MODIFY `created_by` VARCHAR(64) NOT NULL',
    'ALTER TABLE `friendships` MODIFY `owner_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `friendships` MODIFY `friend_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `friendships` MODIFY `individual_ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `user_blocks` MODIFY `blocker_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `user_blocks` MODIFY `blocked_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `ledger_members` MODIFY `ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `ledger_members` MODIFY `user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `ledger_members` MODIFY `added_by` VARCHAR(64) NULL',
    'ALTER TABLE `expenses` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `expenses` MODIFY `ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `expenses` MODIFY `created_by` VARCHAR(64) NOT NULL',
    'ALTER TABLE `expenses` MODIFY `deleted_by` VARCHAR(64) NULL',
    'ALTER TABLE `expense_payers` MODIFY `expense_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `expense_payers` MODIFY `user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `expense_splits` MODIFY `expense_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `expense_splits` MODIFY `user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `disputes` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `disputes` MODIFY `expense_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `disputes` MODIFY `raised_by` VARCHAR(64) NOT NULL',
    'ALTER TABLE `offsets` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `offsets` MODIFY `group_ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `offsets` MODIFY `individual_ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `offsets` MODIFY `from_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `offsets` MODIFY `to_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `offsets` MODIFY `created_by` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlements` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlements` MODIFY `ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlements` MODIFY `from_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlements` MODIFY `to_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlements` MODIFY `offset_id` VARCHAR(64) NULL',
    'ALTER TABLE `settlements` MODIFY `replaced_by_id` VARCHAR(64) NULL',
    'ALTER TABLE `settlements` MODIFY `created_by` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlements` MODIFY `responded_by` VARCHAR(64) NULL',
    'ALTER TABLE `settlement_events` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlement_events` MODIFY `settlement_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `settlement_events` MODIFY `actor_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `activity_log` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `activity_log` MODIFY `ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `activity_log` MODIFY `actor_user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `activity_log` MODIFY `entity_id` VARCHAR(64) NULL',
    'ALTER TABLE `trip_budget_alerts` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `trip_budget_alerts` MODIFY `ledger_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `notifications` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `notifications` MODIFY `user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `device_tokens` MODIFY `id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `device_tokens` MODIFY `user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `idempotency_keys` MODIFY `user_id` VARCHAR(64) NOT NULL',
    'ALTER TABLE `idempotency_keys` MODIFY `resource_id` VARCHAR(64) NULL',
  ];

  for (const sql of columnModifications) {
    try {
      await knex.raw(sql);
    } catch {
      // Ignore if table/column does not exist
    }
  }

  const fksToRecreate = [
    'ALTER TABLE `ledgers` ADD CONSTRAINT `ledgers_created_by_foreign` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)',
    'ALTER TABLE `friendships` ADD CONSTRAINT `friendships_owner_user_id_foreign` FOREIGN KEY (`owner_user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `friendships` ADD CONSTRAINT `friendships_friend_user_id_foreign` FOREIGN KEY (`friend_user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `friendships` ADD CONSTRAINT `friendships_individual_ledger_id_foreign` FOREIGN KEY (`individual_ledger_id`) REFERENCES `ledgers` (`id`)',
    'ALTER TABLE `ledger_members` ADD CONSTRAINT `ledger_members_ledger_id_foreign` FOREIGN KEY (`ledger_id`) REFERENCES `ledgers` (`id`)',
    'ALTER TABLE `ledger_members` ADD CONSTRAINT `ledger_members_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `expenses` ADD CONSTRAINT `expenses_ledger_id_foreign` FOREIGN KEY (`ledger_id`) REFERENCES `ledgers` (`id`)',
    'ALTER TABLE `expenses` ADD CONSTRAINT `expenses_created_by_foreign` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)',
    'ALTER TABLE `expense_payers` ADD CONSTRAINT `expense_payers_expense_id_foreign` FOREIGN KEY (`expense_id`) REFERENCES `expenses` (`id`)',
    'ALTER TABLE `expense_payers` ADD CONSTRAINT `expense_payers_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `expense_splits` ADD CONSTRAINT `expense_splits_expense_id_foreign` FOREIGN KEY (`expense_id`) REFERENCES `expenses` (`id`)',
    'ALTER TABLE `expense_splits` ADD CONSTRAINT `expense_splits_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `settlements` ADD CONSTRAINT `settlements_ledger_id_foreign` FOREIGN KEY (`ledger_id`) REFERENCES `ledgers` (`id`)',
    'ALTER TABLE `settlements` ADD CONSTRAINT `settlements_from_user_id_foreign` FOREIGN KEY (`from_user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `settlements` ADD CONSTRAINT `settlements_to_user_id_foreign` FOREIGN KEY (`to_user_id`) REFERENCES `users` (`id`)',
    'ALTER TABLE `activity_log` ADD CONSTRAINT `activity_log_ledger_id_foreign` FOREIGN KEY (`ledger_id`) REFERENCES `ledgers` (`id`)',
    'ALTER TABLE `notifications` ADD CONSTRAINT `notifications_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)',
  ];

  for (const sql of fksToRecreate) {
    try {
      await knex.raw(sql);
    } catch {
      // Ignore
    }
  }

  await knex.raw('SET FOREIGN_KEY_CHECKS = 1');
}

export async function down(knex: Knex): Promise<void> {
  // Irreversible column width expansion
}
