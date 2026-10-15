// Explicitly configure test environment pointing ONLY to splitup_test
process.env.DB_NAME = 'splitup_test';
process.env.NODE_ENV = 'test';
process.env.PORT = '4005';

const { db } = await import('../dist/db/knex.js');
const { app } = await import('../dist/app.js');
const { getLedgerBalancesFromDb, getUserTotalsFromDb } = await import('../dist/modules/balances/sqlBalances.js');

async function main() {

  console.log('========================================================');
  console.log('   STAGE 1 VERIFICATION TEST SUITE (ON splitup_test)   ');
  console.log('========================================================\n');

  // Verify connected DB
  const [dbNameRow] = await db.raw('SELECT DATABASE() as db');
  const currentDb = dbNameRow[0].db;
  console.log(`Connected to database: ${currentDb}`);
  if (currentDb !== 'splitup_test') {
    throw new Error(`SAFETY CHECK FAILED: Connected to ${currentDb} instead of splitup_test! Aborting immediately.`);
  }

  // 1. Ensure schema in splitup_test
  console.log('\n--- 1. Ensuring Schema on splitup_test ---');
  const hasUsers = await db.schema.hasTable('users');
  if (!hasUsers) {
    console.log('Running knex migrations on splitup_test...');
    await db.migrate.latest({
      directory: './dist/db/migrations',
      loadExtensions: ['.js'],
    });
  }


  // Ensure ID columns are VARCHAR(64) on splitup_test
  await db.raw('SET FOREIGN_KEY_CHECKS = 0');
  const tableCols = [
    ['users', 'id', 'VARCHAR(64) NOT NULL'],
    ['users', 'created_by', 'VARCHAR(64) NULL'],
    ['ledgers', 'id', 'VARCHAR(64) NOT NULL'],
    ['ledgers', 'pair_low_user_id', 'VARCHAR(64) NULL'],
    ['ledgers', 'pair_high_user_id', 'VARCHAR(64) NULL'],
    ['ledgers', 'created_by', 'VARCHAR(64) NOT NULL'],
    ['friendships', 'owner_user_id', 'VARCHAR(64) NOT NULL'],
    ['friendships', 'friend_user_id', 'VARCHAR(64) NOT NULL'],
    ['friendships', 'individual_ledger_id', 'VARCHAR(64) NOT NULL'],
    ['ledger_members', 'ledger_id', 'VARCHAR(64) NOT NULL'],
    ['ledger_members', 'user_id', 'VARCHAR(64) NOT NULL'],
    ['expenses', 'id', 'VARCHAR(64) NOT NULL'],
    ['expenses', 'ledger_id', 'VARCHAR(64) NOT NULL'],
    ['expenses', 'created_by', 'VARCHAR(64) NOT NULL'],
    ['expense_payers', 'expense_id', 'VARCHAR(64) NOT NULL'],
    ['expense_payers', 'user_id', 'VARCHAR(64) NOT NULL'],
    ['expense_splits', 'expense_id', 'VARCHAR(64) NOT NULL'],
    ['expense_splits', 'user_id', 'VARCHAR(64) NOT NULL'],
    ['settlements', 'id', 'VARCHAR(64) NOT NULL'],
    ['settlements', 'ledger_id', 'VARCHAR(64) NOT NULL'],
    ['settlements', 'from_user_id', 'VARCHAR(64) NOT NULL'],
    ['settlements', 'to_user_id', 'VARCHAR(64) NOT NULL'],
    ['activity_log', 'ledger_id', 'VARCHAR(64) NOT NULL'],
    ['activity_log', 'actor_user_id', 'VARCHAR(64) NOT NULL'],
    ['notifications', 'id', 'VARCHAR(64) NOT NULL'],
    ['notifications', 'user_id', 'VARCHAR(64) NOT NULL'],
    ['idempotency_keys', 'user_id', 'VARCHAR(64) NOT NULL'],
    ['idempotency_keys', 'key_value', 'VARCHAR(64) NOT NULL'],
  ];


  for (const [tbl, col, def] of tableCols) {
    try {
      if (await db.schema.hasTable(tbl)) {
        await db.raw(`ALTER TABLE \`${tbl}\` MODIFY \`${col}\` ${def}`);
      }
    } catch (e) {
      // ignore
    }
  }
  await db.raw('SET FOREIGN_KEY_CHECKS = 1');
  console.log('Schema verified on splitup_test.');

  // Clean test data in splitup_test
  await db.raw('SET FOREIGN_KEY_CHECKS = 0');
  await db('activity_log').truncate();
  await db('expense_splits').truncate();
  await db('expense_payers').truncate();
  await db('expenses').truncate();
  await db('settlements').truncate();
  await db('friendships').truncate();
  await db('ledger_members').truncate();
  await db('ledgers').truncate();
  await db('idempotency_keys').truncate();
  await db('users').whereIn('id', ['usr_test_a', 'usr_test_b', 'usr_test_c']).delete();
  await db.raw('SET FOREIGN_KEY_CHECKS = 1');
  console.log('Cleaned test tables.');

  // 2. Seed test users and individual ledger
  console.log('\n--- 2. Seeding Test Users & Individual Ledger ---');
  const now = new Date();
  await db('users').insert([
    {
      id: 'usr_test_a',
      phone_e164: '+919999900001',
      name: 'Alice',
      is_placeholder: 0,
      status: 'ACTIVE',
      created_at: now,
      updated_at: now,
    },
    {
      id: 'usr_test_b',
      phone_e164: '+919999900002',
      name: 'Bob',
      is_placeholder: 0,
      status: 'ACTIVE',
      created_at: now,
      updated_at: now,
    },
    {
      id: 'usr_test_c',
      phone_e164: '+919999900003',
      name: 'Charlie (Non-Member)',
      is_placeholder: 0,
      status: 'ACTIVE',
      created_at: now,
      updated_at: now,
    },
  ]);

  const testLedgerId = 'ldg_test_alice_bob';
  await db('ledgers').insert({
    id: testLedgerId,
    type: 'INDIVIDUAL',
    name: 'Alice & Bob',
    status: 'ACTIVE',
    pair_low_user_id: 'usr_test_a',
    pair_high_user_id: 'usr_test_b',
    created_by: 'usr_test_a',
    created_at: now,
    updated_at: now,
  });

  await db('ledger_members').insert([
    { ledger_id: testLedgerId, user_id: 'usr_test_a', role: 'MEMBER', joined_at: now },
    { ledger_id: testLedgerId, user_id: 'usr_test_b', role: 'MEMBER', joined_at: now },
  ]);

  await db('friendships').insert([
    {
      owner_user_id: 'usr_test_a',
      friend_user_id: 'usr_test_b',
      individual_ledger_id: testLedgerId,
      created_at: now,
    },
    {
      owner_user_id: 'usr_test_b',
      friend_user_id: 'usr_test_a',
      individual_ledger_id: testLedgerId,
      created_at: now,
    },
  ]);

  console.log('Seeded Alice, Bob, Charlie and individual ledger:', testLedgerId);

  // Start test HTTP server
  const server = app.listen(4005);
  const baseUrl = 'http://127.0.0.1:4005';

  try {
    // -------------------------------------------------------------
    // TEST 1: Alice creates an expense of ₹1,200 (120,000 paise) split equally
    // -------------------------------------------------------------
    console.log('\n--- TEST 1: Alice creates ₹1,200 equal expense with Bob ---');
    const exp1Res = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer user:usr_test_a',
      },
      body: JSON.stringify({
        title: 'Team Lunch',
        totalPaise: 120000,
        category: 'food',
        splitType: 'EQUAL',
        payers: [{ userId: 'usr_test_a', paidPaise: 120000 }],
        participants: [
          { userId: 'usr_test_a', included: true },
          { userId: 'usr_test_b', included: true },
        ],
      }),
    });

    const exp1Json = await exp1Res.json();
    console.log(`Expense 1 creation HTTP status: ${exp1Res.status}`);
    if (exp1Res.status !== 201) {
      throw new Error(`Expense 1 creation failed: ${JSON.stringify(exp1Json)}`);
    }
    const exp1 = exp1Json.data;
    console.log(`Created expense ID: ${exp1.id}, total: ₹${exp1.totalPaise / 100}`);

    // Verify Bob can immediately fetch the expense from the server
    const bListRes = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      headers: { Authorization: 'Bearer user:usr_test_b' },
    });
    const bListJson = await bListRes.json();
    console.log(`Bob fetched expenses count: ${bListJson.data.length}`);
    if (bListJson.data.length !== 1 || bListJson.data[0].id !== exp1.id) {
      throw new Error(`Bob did not see the newly created expense!`);
    }
    console.log('✅ PASS: Bob immediately sees expense added by Alice');

    // Check ledger balances
    const bal1Res = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/balances`, {
      headers: { Authorization: 'Bearer user:usr_test_b' },
    });
    const bal1Json = await bal1Res.json();
    console.log('Ledger balances after Exp 1:', bal1Json.data.balances);
    if (bal1Json.data.balances.usr_test_a !== 60000 || bal1Json.data.balances.usr_test_b !== -60000) {
      throw new Error(`Unexpected balances after Exp 1: ${JSON.stringify(bal1Json.data.balances)}`);
    }
    console.log('✅ PASS: Ledger balances match: Alice = +60,000, Bob = -60,000');

    // Check Alice totals
    const aTotalsRes = await fetch(`${baseUrl}/v1/users/me/totals`, {
      headers: { Authorization: 'Bearer user:usr_test_a' },
    });
    const aTotals = (await aTotalsRes.json()).data;
    console.log('Alice totals:', aTotals);
    if (aTotals.totalReceivablePaise !== 60000 || aTotals.totalOwedPaise !== 0 || aTotals.netPaise !== 60000) {
      throw new Error(`Alice totals mismatch: ${JSON.stringify(aTotals)}`);
    }
    console.log('✅ PASS: Alice totals match: receivable = 60000, owed = 0, net = +60000');

    // Check Bob totals
    const bTotalsRes = await fetch(`${baseUrl}/v1/users/me/totals`, {
      headers: { Authorization: 'Bearer user:usr_test_b' },
    });
    const bTotals = (await bTotalsRes.json()).data;
    console.log('Bob totals:', bTotals);
    if (bTotals.totalReceivablePaise !== 0 || bTotals.totalOwedPaise !== 60000 || bTotals.netPaise !== -60000) {
      throw new Error(`Bob totals mismatch: ${JSON.stringify(bTotals)}`);
    }
    console.log('✅ PASS: Bob totals match: receivable = 0, owed = 60000, net = -60000');

    // -------------------------------------------------------------
    // TEST 2: Bob adds an expense of ₹400 (40,000 paise) split equally
    // -------------------------------------------------------------
    console.log('\n--- TEST 2: Bob adds ₹400 equal expense with Alice ---');
    const exp2Res = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer user:usr_test_b',
      },
      body: JSON.stringify({
        title: 'Coffee & Snacks',
        totalPaise: 40000,
        category: 'food',
        splitType: 'EQUAL',
        payers: [{ userId: 'usr_test_b', paidPaise: 40000 }],
        participants: [
          { userId: 'usr_test_a', included: true },
          { userId: 'usr_test_b', included: true },
        ],
      }),
    });

    const exp2Json = await exp2Res.json();
    console.log(`Expense 2 creation HTTP status: ${exp2Res.status}`);
    if (exp2Res.status !== 201) {
      throw new Error(`Expense 2 creation failed: ${JSON.stringify(exp2Json)}`);
    }

    // Verify net balances: Alice paid 1200, owed 600 + 200 = 800. Net Alice = +400 (+40,000 paise).
    // Bob paid 400, owed 600 + 200 = 800. Net Bob = -400 (-40,000 paise).
    const bal2Res = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/balances`, {
      headers: { Authorization: 'Bearer user:usr_test_a' },
    });
    const bal2Json = await bal2Res.json();
    console.log('Ledger balances after Exp 2:', bal2Json.data.balances);
    if (bal2Json.data.balances.usr_test_a !== 40000 || bal2Json.data.balances.usr_test_b !== -40000) {
      throw new Error(`Unexpected balances after Exp 2: ${JSON.stringify(bal2Json.data.balances)}`);
    }
    console.log('✅ PASS: Net balance after two expenses: Bob owes Alice ₹400 (40,000 paise)');

    // Verify GET /v1/friends for Alice: netPaise = +40000 (Bob owes Alice)
    const aFriendsRes = await fetch(`${baseUrl}/v1/friends`, {
      headers: { Authorization: 'Bearer user:usr_test_a' },
    });
    const aFriendsJson = await aFriendsRes.json();
    const bobFriend = aFriendsJson.data.find((f) => f.friendId === 'usr_test_b');
    console.log(`Alice friend Bob netPaise: ${bobFriend?.netPaise}`);
    if (bobFriend?.netPaise !== 40000) {
      throw new Error(`Alice friend list shows wrong netPaise for Bob: ${bobFriend?.netPaise}`);
    }
    console.log('✅ PASS: Alice GET /v1/friends shows Bob owes +40,000 paise');

    // Verify GET /v1/friends for Bob: netPaise = -40000 (Bob owes Alice)
    const bFriendsRes = await fetch(`${baseUrl}/v1/friends`, {
      headers: { Authorization: 'Bearer user:usr_test_b' },
    });
    const bFriendsJson = await bFriendsRes.json();
    const aliceFriend = bFriendsJson.data.find((f) => f.friendId === 'usr_test_a');
    console.log(`Bob friend Alice netPaise: ${aliceFriend?.netPaise}`);
    if (aliceFriend?.netPaise !== -40000) {
      throw new Error(`Bob friend list shows wrong netPaise for Alice: ${aliceFriend?.netPaise}`);
    }
    console.log('✅ PASS: Bob GET /v1/friends shows Bob owes Alice -40,000 paise');

    // -------------------------------------------------------------
    // TEST 3: Cold Start test (direct DB computation, zero memory)
    // -------------------------------------------------------------
    console.log('\n--- TEST 3: Cold Start DB Computation ---');
    const coldBalances = await getLedgerBalancesFromDb(testLedgerId);
    console.log('Cold query balances:', coldBalances);
    if (coldBalances.usr_test_a !== 40000 || coldBalances.usr_test_b !== -40000) {
      throw new Error('Cold DB balance query returned incorrect balances');
    }
    const coldTotalsA = await getUserTotalsFromDb('usr_test_a');
    if (coldTotalsA.netPaise !== 40000) {
      throw new Error('Cold DB totals query returned incorrect totals');
    }
    console.log('✅ PASS: Cold start queries calculate exact same balances directly from MySQL');

    // -------------------------------------------------------------
    // TEST 4: Forced DB Rollback Test
    // -------------------------------------------------------------
    console.log('\n--- TEST 4: Forced Transaction Rollback Test ---');
    const countBeforeExp = await db('expenses').where({ ledger_id: testLedgerId }).count('* as c');
    const initialCount = Number(countBeforeExp[0].c);

    try {
      await db.transaction(async (trx) => {
        await trx('expenses').insert({
          id: 'exp_rollback_test',
          ledger_id: testLedgerId,
          title: 'Rollback Expense',
          total_paise: 50000,
          category: 'other',
          split_type: 'EQUAL',
          created_by: 'usr_test_a',
          created_at: new Date(),
          updated_at: new Date(),
        });

        // Intentional failure: violate foreign key on non-existent user in payers
        await trx('expense_payers').insert({
          expense_id: 'exp_rollback_test',
          user_id: 'non_existent_user_99999',
          paid_paise: 50000,
        });
      });
    } catch (expectedErr) {
      console.log('Caught expected error in mid-transaction:', expectedErr.message);
    }

    const countAfterExp = await db('expenses').where({ ledger_id: testLedgerId }).count('* as c');
    const finalCount = Number(countAfterExp[0].c);
    if (finalCount !== initialCount) {
      throw new Error(`Rollback failed! Expense count changed from ${initialCount} to ${finalCount}`);
    }
    console.log('✅ PASS: Forced rollback left 0 orphaned rows in MySQL');

    // -------------------------------------------------------------
    // TEST 5: Idempotency Key Handling
    // -------------------------------------------------------------
    console.log('\n--- TEST 5: Idempotency Key Handling ---');
    const idempKey = 'idemp_key_' + Date.now();
    const idempPayload = {
      title: 'Groceries with Idempotency',
      totalPaise: 30000,
      category: 'groceries',
      splitType: 'EQUAL',
      payers: [{ userId: 'usr_test_a', paidPaise: 30000 }],
      participants: [
        { userId: 'usr_test_a', included: true },
        { userId: 'usr_test_b', included: true },
      ],
    };

    // First request
    const idemp1Res = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer user:usr_test_a',
        'Idempotency-Key': idempKey,
      },
      body: JSON.stringify(idempPayload),
    });
    const idemp1Json = await idemp1Res.json();
    console.log(`Idempotency 1st call status: ${idemp1Res.status}, expense ID: ${idemp1Json.data.id}`);
    if (idemp1Res.status !== 201) {
      throw new Error('Idempotent 1st call failed');
    }

    // Duplicate request with SAME key and SAME body
    const idemp2Res = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer user:usr_test_a',
        'Idempotency-Key': idempKey,
      },
      body: JSON.stringify(idempPayload),
    });
    const idemp2Json = await idemp2Res.json();
    console.log(`Idempotency duplicate call status: ${idemp2Res.status}, expense ID: ${idemp2Json.data.id}`);
    if (idemp2Res.status !== 201 || idemp2Json.data.id !== idemp1Json.data.id) {
      throw new Error('Idempotent duplicate did not return cached identical expense!');
    }
    console.log('✅ PASS: Re-sent request with same Idempotency-Key returned cached response without duplicate row');

    // Conflicting request with SAME key but DIFFERENT body
    const idempConflictRes = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer user:usr_test_a',
        'Idempotency-Key': idempKey,
      },
      body: JSON.stringify({ ...idempPayload, totalPaise: 99999 }),
    });
    console.log(`Idempotency conflict call status: ${idempConflictRes.status}`);
    if (idempConflictRes.status !== 409) {
      throw new Error(`Expected 409 Conflict on payload mismatch, got ${idempConflictRes.status}`);
    }
    console.log('✅ PASS: Mismatched payload with used Idempotency-Key returns 409 Conflict');

    // -------------------------------------------------------------
    // TEST 6: Authorization & Membership Enforcement
    // -------------------------------------------------------------
    console.log('\n--- TEST 6: Authorization & Membership Enforcement ---');
    // Non-member Charlie tries to access Alice & Bob ledger
    const forbiddenRes = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`, {
      headers: { Authorization: 'Bearer user:usr_test_c' },
    });
    console.log(`Non-member access status: ${forbiddenRes.status}`);
    if (forbiddenRes.status !== 403) {
      throw new Error(`Expected 403 Forbidden for non-member, got ${forbiddenRes.status}`);
    }
    console.log('✅ PASS: Non-member gets 403 Forbidden');

    // Unauthenticated request (no Authorization header)
    const unauthRes = await fetch(`${baseUrl}/v1/ledgers/${testLedgerId}/expenses`);
    console.log(`Unauthenticated access status: ${unauthRes.status}`);
    if (unauthRes.status !== 401) {
      throw new Error(`Expected 401 Unauthenticated for missing auth, got ${unauthRes.status}`);
    }
    console.log('✅ PASS: Missing Authorization header gets 401 Unauthenticated (fallback to usr_arhaam eliminated)');

    // -------------------------------------------------------------
    // TEST 7: Zero-Sum Invariant Across Ledger
    // -------------------------------------------------------------
    console.log('\n--- TEST 7: Zero-Sum Invariant Check ---');
    const finalBalances = await getLedgerBalancesFromDb(testLedgerId);
    let totalNet = 0;
    for (const [uid, net] of Object.entries(finalBalances)) {
      totalNet += net;
      console.log(`  User ${uid}: ${net} paise`);
    }
    console.log(`Total sum across all ledger members: ${totalNet} paise`);
    if (totalNet !== 0) {
      throw new Error(`Zero-sum invariant violated! Total net = ${totalNet}`);
    }
    console.log('✅ PASS: Zero-sum invariant verified: sum(balances) === 0');

    console.log('\n========================================================');
    console.log('   🎉 ALL STAGE 1 VERIFICATION TESTS PASSED SUCCESSFULLY! ');
    console.log('========================================================');
  } finally {
    server.close();
    await db.destroy();
  }
}

main().catch((err) => {
  console.error('\n❌ TEST RUNNER FAILED:', err);
  process.exit(1);
});
