const { Client } = require('pg');

async function main() {
  const client = new Client({
    host: 'aws-0-ap-northeast-1.pooler.supabase.com',
    port: 6543,
    user: 'postgres.cnwtprexxjrajcdjhfsr',
    password: 'RRaunak@7176',
    database: 'postgres',
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15000,
  });

  await client.connect();

  const sql = `
    CREATE OR REPLACE FUNCTION public.fn_can_manage_content(p_user_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
    AS $$
      SELECT CASE
        WHEN p_user_id IS NULL THEN false
        ELSE EXISTS (
          SELECT 1
          FROM public.group_members gm
          WHERE gm.user_id = p_user_id
            AND public.fn_has_permission(gm.group_id, p_user_id, 'GENERATE_QUESTIONS'::app_permission)
        )
      END;
    $$;

    GRANT EXECUTE ON FUNCTION public.fn_can_manage_content(uuid) TO anon, authenticated, service_role;

    DROP POLICY IF EXISTS "Public read published chapters" ON public.chapters;
    CREATE POLICY "Public read published chapters" ON public.chapters
      FOR SELECT USING (
        (status = 'published' AND is_active = true)
        OR (auth.uid() IS NOT NULL AND fn_can_manage_content(auth.uid()))
      );

    DROP POLICY IF EXISTS "Public read published topics" ON public.topics;
    CREATE POLICY "Public read published topics" ON public.topics
      FOR SELECT USING (
        (status = 'published' AND is_active = true)
        OR (auth.uid() IS NOT NULL AND fn_can_manage_content(auth.uid()))
      );

    DROP POLICY IF EXISTS "Public read published content blocks" ON public.content_blocks;
    CREATE POLICY "Public read published content blocks" ON public.content_blocks
      FOR SELECT USING (
        (status = 'published' AND is_active = true)
        OR (auth.uid() IS NOT NULL AND fn_can_manage_content(auth.uid()))
      );
  `;

  await client.query(sql);
  console.log('Successfully hardened study RLS policies with SECURITY DEFINER function!');
  await client.end();
}

main().catch(err => {
  console.error('Migration error:', err);
  process.exit(1);
});

