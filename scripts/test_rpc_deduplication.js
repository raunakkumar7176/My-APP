const { Client } = require('pg');

async function testRpcDeduplication() {
  const client = new Client({
    host: 'aws-0-ap-northeast-1.pooler.supabase.com',
    port: 6543,
    user: 'postgres.cnwtprexxjrajcdjhfsr',
    password: 'RRaunak@7176',
    database: 'postgres',
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15000,
  });

  const testUserId = '78e09bb0-889f-414e-9262-317b941f74c2';
  const testQuestionText = 'What is the capital of France? (Phase 1 Automated Test Verification ' + Date.now() + ')';
  const createdIds = [];

  try {
    await client.connect();
    console.log('Connected to database.');

    // Pre-cleanup in case of prior runs
    await client.query("DELETE FROM public.question_bank WHERE question LIKE '%Phase 1 Automated Test Verification%';");

    // Start a transaction for controlled testing
    await client.query('BEGIN;');

    // Set auth context for auth.uid()
    await client.query(`
      SELECT set_config('request.jwt.claims', $1, true);
    `, [JSON.stringify({ sub: testUserId, role: 'authenticated' })]);

    // Verify auth.uid()
    const authCheck = await client.query('SELECT auth.uid() as uid;');
    console.log('Active simulated auth.uid():', authCheck.rows[0].uid);
    if (authCheck.rows[0].uid !== testUserId) {
      throw new Error('auth.uid() simulation failed');
    }

    console.log('\n--- TEST 1: INTRA-BATCH DEDUPLICATION ---');
    const intraBatchPayload = [
      {
        question: testQuestionText,
        options: ['Berlin', 'Paris', 'Rome', 'Madrid'],
        correct_option: 1,
        explanation: 'Paris is France capital.'
      },
      {
        question: testQuestionText,
        options: ['Berlin', 'Paris', 'Rome', 'Madrid'],
        correct_option: 1,
        explanation: 'Paris is France capital.'
      }
    ];

    const res1 = await client.query(
      `SELECT public.rpc_save_drafts_to_question_bank($1, NULL, NULL, 'upload', 'pending_review') as result;`,
      [JSON.stringify(intraBatchPayload)]
    );

    const r1 = res1.rows[0].result;
    console.log('Test 1 Result:', JSON.stringify(r1, null, 2));

    if (r1.total !== 2) throw new Error(`Expected total 2, got ${r1.total}`);
    if (r1.saved_count !== 1) throw new Error(`Expected saved_count 1, got ${r1.saved_count}`);
    if (r1.skipped_duplicate_count !== 1) throw new Error(`Expected skipped_duplicate_count 1, got ${r1.skipped_duplicate_count}`);
    if (r1.saved_ids.length !== 1) throw new Error(`Expected 1 saved_id, got ${r1.saved_ids.length}`);
    if (r1.skipped_duplicates[0].reason !== 'DUPLICATE_IN_BATCH') {
      throw new Error(`Expected reason DUPLICATE_IN_BATCH, got ${r1.skipped_duplicates[0].reason}`);
    }
    createdIds.push(...r1.saved_ids);
    console.log('✅ TEST 1 PASSED: Intra-batch deduplication verified (saved: 1, skipped: 1)');

    console.log('\n--- TEST 2: TABLE-LEVEL DEDUPLICATION ---');
    const tableBatchPayload = [
      {
        question: testQuestionText,
        options: ['Berlin', 'Paris', 'Rome', 'Madrid'],
        correct_option: 1,
        explanation: 'Paris is France capital.'
      }
    ];

    const res2 = await client.query(
      `SELECT public.rpc_save_drafts_to_question_bank($1, NULL, NULL, 'upload', 'pending_review') as result;`,
      [JSON.stringify(tableBatchPayload)]
    );

    const r2 = res2.rows[0].result;
    console.log('Test 2 Result:', JSON.stringify(r2, null, 2));

    if (r2.total !== 1) throw new Error(`Expected total 1, got ${r2.total}`);
    if (r2.saved_count !== 0) throw new Error(`Expected saved_count 0, got ${r2.saved_count}`);
    if (r2.skipped_duplicate_count !== 1) throw new Error(`Expected skipped_duplicate_count 1, got ${r2.skipped_duplicate_count}`);
    if (r2.saved_ids.length !== 0) throw new Error(`Expected 0 saved_ids, got ${r2.saved_ids.length}`);
    if (r2.skipped_duplicates[0].reason !== 'ALREADY_EXISTS_IN_BANK') {
      throw new Error(`Expected reason ALREADY_EXISTS_IN_BANK, got ${r2.skipped_duplicates[0].reason}`);
    }
    console.log('✅ TEST 2 PASSED: Table-level deduplication verified (saved: 0, skipped: 1)');

    console.log('\n--- TEST 3: RETURNED JSON STRUCTURE VERIFICATION ---');
    const requiredKeys = ['total', 'saved_count', 'saved_ids', 'skipped_duplicate_count', 'skipped_duplicates'];
    for (const key of requiredKeys) {
      if (!(key in r1) || !(key in r2)) {
        throw new Error(`Missing expected key in RPC response: ${key}`);
      }
    }
    console.log('✅ TEST 3 PASSED: JSON structure strictly matches required schema');

    // Clean up
    console.log('\n--- TEST 4: ISOLATED CLEANUP ---');
    await client.query('ROLLBACK;'); // Rollback entire transaction so zero pollution remains
    console.log('✅ TEST 4 PASSED: Cleaned up test data via transaction rollback');

  } catch (err) {
    console.error('❌ DEDUPLICATION TEST FAILED:', err);
    try { await client.query('ROLLBACK;'); } catch (_) {}
    process.exit(1);
  } finally {
    await client.end();
  }
}

testRpcDeduplication();
