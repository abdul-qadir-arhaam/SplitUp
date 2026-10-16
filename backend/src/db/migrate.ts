import { db } from './knex.js';

async function run() {
  console.log('Testing TiDB Cloud MySQL connection...');
  const [result] = await db.raw('SELECT 1 as connected');
  console.log('Connection successful:', result);

  console.log('Running schema migrations on TiDB...');
  const [batchNo, log] = await db.migrate.latest({
    directory: './src/db/migrations',
    extension: 'ts',
    loadExtensions: ['.ts'],
  });
  console.log(`Batch ${batchNo} completed: ${log.length} migrations executed.`);
  for (const m of log) {
    console.log(` - ${m}`);
  }

  const [tables] = await db.raw('SHOW TABLES');
  console.log('Current tables in database:');
  console.table(tables);

  await db.destroy();
  console.log('Database setup complete.');
}

run().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
