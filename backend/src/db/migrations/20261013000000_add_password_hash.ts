import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  const hasCol = await knex.schema.hasColumn('users', 'password_hash');
  if (!hasCol) {
    await knex.schema.alterTable('users', (table) => {
      table.string('password_hash', 255).nullable();
    });
  }
}

export async function down(knex: Knex): Promise<void> {
  const hasCol = await knex.schema.hasColumn('users', 'password_hash');
  if (hasCol) {
    await knex.schema.alterTable('users', (table) => {
      table.dropColumn('password_hash');
    });
  }
}
