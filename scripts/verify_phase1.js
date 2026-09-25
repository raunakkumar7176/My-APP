const { Client } = require('pg');

async function runAudit() {
  const client = new Client({
    host: 'aws-0-ap-northeast-1.pooler.supabase.com',
    port: 6543,
    user: 'postgres.cnwtprexxjrajcdjhfsr',
    password: 'RRaunak@7176',
    database: 'postgres',
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15000,
  });

  try {
    await client.connect();
    console.log('Connected to Supabase PostgreSQL database.');

    console.log('\n--- 1. DATABASE SCHEMA & RPC AUDIT ---');

    // 1. Check is_ephemeral column in uploaded_documents
    const colRes = await client.query(`
      SELECT column_name, data_type, column_default, is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'uploaded_documents'
        AND column_name = 'is_ephemeral';
    `);
    console.log('Column is_ephemeral check:', colRes.rows);

    // 2. Check index idx_uploaded_documents_ephemeral_purge
    const idxRes = await client.query(`
      SELECT indexname, indexdef
      FROM pg_indexes
      WHERE schemaname = 'public'
        AND tablename = 'uploaded_documents'
        AND indexname = 'idx_uploaded_documents_ephemeral_purge';
    `);
    console.log('Index check:', idxRes.rows);

    // 3. Check RPC existence, arguments, and SECURITY DEFINER
    const rpcRes = await client.query(`
      SELECT 
        p.proname,
        pg_get_function_identity_arguments(p.oid) as args,
        p.prosecdef as is_security_definer,
        r.rolname as owner
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      JOIN pg_roles r ON p.proowner = r.oid
      WHERE n.nspname = 'public'
        AND p.proname IN ('rpc_purge_ephemeral_documents', 'rpc_save_drafts_to_question_bank');
    `);
    console.log('RPC check:', rpcRes.rows);

  } catch (err) {
    console.error('Audit query error:', err);
  } finally {
    await client.end();
  }
}

runAudit();
