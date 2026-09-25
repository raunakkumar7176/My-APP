-- ============================================================================
-- Phase 1 — Database & Storage Foundations
-- My Preparation — Flutter + Supabase
--
-- PURPOSE:
-- 1. Zero-Leak Storage Lifecycle:
--    - Adds `is_ephemeral` flag to `public.uploaded_documents`.
--    - Adds server-side purge routine `rpc_purge_ephemeral_documents` for
--      automatic and cancellation/post-processing purging of temporary files
--      in the `test-documents` bucket.
-- 2. Question Bank Save Bridge:
--    - Adds `rpc_save_drafts_to_question_bank` with strict user isolation (auth.uid()),
--      in-batch and bank-wide duplicate key protection, and optional
--      subject_id / chapter_id hierarchy mapping.
--
-- ARCHITECTURE CONTRACT:
-- - 100% Additive: Non-destructive to existing columns, tables, or active tests.
-- - Security Definer with strict `SET search_path TO ''`.
-- - Auth Isolation: Uses `auth.uid()`; anonymous and PUBLIC execution revoked.
-- - Idempotent and Rollback-Safe.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: ZERO-LEAK STORAGE LIFECYCLE (uploaded_documents + purge routine)
-- ============================================================================

-- 1.1 Add is_ephemeral flag to uploaded_documents
ALTER TABLE public.uploaded_documents
  ADD COLUMN IF NOT EXISTS is_ephemeral boolean NOT NULL DEFAULT true;

-- 1.2 Performance index for ephemeral document lifecycle & cleanup queries
CREATE INDEX IF NOT EXISTS idx_uploaded_documents_ephemeral_purge
  ON public.uploaded_documents (uploaded_by, is_ephemeral, created_at)
  WHERE is_ephemeral = true;

-- 1.3 Server-side purge routine for ephemeral documents
-- Purges both the storage.objects entry in 'test-documents' and the metadata row.
-- Can be called with a specific document_id (e.g. on user cancellation / import completion)
-- or without (to purge expired ephemeral uploads older than p_max_age_minutes).
CREATE OR REPLACE FUNCTION public.rpc_purge_ephemeral_documents(
  p_document_id uuid DEFAULT NULL,
  p_max_age_minutes integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  v_doc record;
  v_purged_ids uuid[] := '{}';
  v_purged_paths text[] := '{}';
  v_cutoff timestamptz;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_cutoff := now() - (coalesce(p_max_age_minutes, 120) || ' minutes')::interval;

  for v_doc in
    select id, storage_path
    from public.uploaded_documents
    where uploaded_by = v_uid
      and is_ephemeral = true
      and (
        (p_document_id is not null and id = p_document_id)
        or
        (p_document_id is null and created_at < v_cutoff)
      )
    for update
  loop
    -- Delete file from storage.objects ensuring user-scoped path security
    -- Storage policy strictly enforces (storage.foldername(name))[1] = auth.uid()::text
    delete from storage.objects
    where bucket_id = 'test-documents'
      and name = v_doc.storage_path
      and (storage.foldername(name))[1] = v_uid::text;

    -- Delete metadata record
    delete from public.uploaded_documents
    where id = v_doc.id;

    v_purged_ids := array_append(v_purged_ids, v_doc.id);
    v_purged_paths := array_append(v_purged_paths, v_doc.storage_path);
  end loop;

  return jsonb_build_object(
    'purged_count', coalesce(array_length(v_purged_ids, 1), 0),
    'purged_ids', to_jsonb(v_purged_ids),
    'purged_paths', to_jsonb(v_purged_paths)
  );
end;
$$;

REVOKE ALL ON FUNCTION public.rpc_purge_ephemeral_documents(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_purge_ephemeral_documents(uuid, integer) TO authenticated, service_role;


-- ============================================================================
-- SECTION 2: QUESTION BANK SAVE BRIDGE (rpc_save_drafts_to_question_bank)
-- ============================================================================

-- Saves drafts into public.question_bank with:
-- 1. auth.uid() isolation (created_by assigned server-side).
-- 2. Duplicate key protection (normalizes question text and skips duplicates).
-- 3. Optional subject_id and chapter_id hierarchy mapping.
CREATE OR REPLACE FUNCTION public.rpc_save_drafts_to_question_bank(
  p_drafts jsonb,
  p_subject_id uuid DEFAULT NULL,
  p_chapter_id uuid DEFAULT NULL,
  p_source text DEFAULT 'upload',
  p_status text DEFAULT 'pending_review'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_question text;
  v_dup_key text;
  v_options jsonb;
  v_correct_opt integer;
  v_explanation text;
  v_subject_id uuid;
  v_subject_name text;
  v_chapter_id uuid;
  v_chapter text;
  v_topic_id uuid;
  v_difficulty text;
  v_language text;
  v_question_type text;
  v_source text;
  v_target_status public.question_status;
  v_new_id uuid;
  v_existing_id uuid;
  v_saved_ids uuid[] := '{}';
  v_skipped jsonb := '[]'::jsonb;
  v_seen_keys text[] := '{}';
  v_opt_arr jsonb;
  v_opt_item jsonb;
  v_formatted_options jsonb;
  v_opt_idx integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_drafts is null or jsonb_typeof(p_drafts) <> 'array' or jsonb_array_length(p_drafts) = 0 then
    return jsonb_build_object(
      'total', 0,
      'saved_count', 0,
      'saved_ids', '[]'::jsonb,
      'skipped_duplicate_count', 0,
      'skipped_duplicates', '[]'::jsonb
    );
  end if;

  if jsonb_array_length(p_drafts) > 100 then
    raise exception 'VALIDATION_ERROR: at most 100 drafts allowed per batch';
  end if;

  -- Validate target question_status enum
  if p_status is not null and p_status in ('pending_review', 'approved') then
    v_target_status := p_status::public.question_status;
  else
    v_target_status := 'pending_review'::public.question_status;
  end if;

  for v_item in select * from jsonb_array_elements(p_drafts)
  loop
    -- Extract and sanitize question text
    v_question := btrim(coalesce(v_item->>'question', v_item->>'question_text', v_item->>'questionText', ''));
    if v_question = '' then
      v_skipped := v_skipped || jsonb_build_object(
        'reason', 'EMPTY_QUESTION_TEXT',
        'raw', v_item
      );
      continue;
    end if;

    -- Calculate normalized duplicate key (lower-cased, whitespace collapsed)
    v_dup_key := lower(regexp_replace(v_question, '\s+', ' ', 'g'));

    -- Check duplicate within current batch
    if v_dup_key = ANY(v_seen_keys) then
      v_skipped := v_skipped || jsonb_build_object(
        'question', v_question,
        'duplicate_key', v_dup_key,
        'reason', 'DUPLICATE_IN_BATCH'
      );
      continue;
    end if;

    -- Check duplicate in public.question_bank
    select id into v_existing_id
    from public.question_bank
    where duplicate_key = v_dup_key
      and (created_by = v_uid or status = 'approved'::public.question_status)
    limit 1;

    if v_existing_id is not null then
      v_skipped := v_skipped || jsonb_build_object(
        'question', v_question,
        'duplicate_key', v_dup_key,
        'existing_id', v_existing_id,
        'reason', 'ALREADY_EXISTS_IN_BANK'
      );
      continue;
    end if;

    -- Track seen duplicate key
    v_seen_keys := array_append(v_seen_keys, v_dup_key);

    -- Format options array: support both [string, ...] and [{id, text}, ...]
    v_opt_arr := v_item->'options';
    v_formatted_options := '[]'::jsonb;
    v_opt_idx := 0;

    if v_opt_arr is not null and jsonb_typeof(v_opt_arr) = 'array' then
      for v_opt_item in select * from jsonb_array_elements(v_opt_arr)
      loop
        v_opt_idx := v_opt_idx + 1;
        if jsonb_typeof(v_opt_item) = 'string' then
          v_formatted_options := v_formatted_options || jsonb_build_object(
            'id', 'opt_' || v_opt_idx::text,
            'text', v_opt_item #>> '{}'
          );
        elsif jsonb_typeof(v_opt_item) = 'object' then
          v_formatted_options := v_formatted_options || jsonb_build_object(
            'id', coalesce(v_opt_item->>'id', 'opt_' || v_opt_idx::text),
            'text', coalesce(v_opt_item->>'text', '')
          );
        end if;
      end loop;
    end if;

    -- Validate options count (minimum 2, standard 4 for MCQ)
    if jsonb_array_length(v_formatted_options) < 2 then
      v_skipped := v_skipped || jsonb_build_object(
        'question', v_question,
        'reason', 'INSUFFICIENT_OPTIONS'
      );
      continue;
    end if;

    -- Extract correct option
    v_correct_opt := coalesce(
      (v_item->>'correct_option')::integer,
      (v_item->>'correctOption')::integer,
      (v_item->>'correctOptionIndex')::integer,
      0
    );

    if v_correct_opt < 0 or v_correct_opt >= jsonb_array_length(v_formatted_options) then
      v_correct_opt := 0;
    end if;

    -- Extract metadata with optional fallback to function arguments
    v_explanation := coalesce(v_item->>'explanation', '');
    v_subject_id := coalesce(
      nullif(v_item->>'subject_id', '')::uuid,
      nullif(v_item->>'subjectId', '')::uuid,
      p_subject_id
    );
    v_chapter_id := coalesce(
      nullif(v_item->>'chapter_id', '')::uuid,
      nullif(v_item->>'chapterId', '')::uuid,
      p_chapter_id
    );
    v_topic_id := coalesce(
      nullif(v_item->>'topic_id', '')::uuid,
      nullif(v_item->>'topicId', '')::uuid,
      null
    );

    v_difficulty := coalesce(v_item->>'difficulty', 'medium');
    if v_difficulty not in ('easy', 'medium', 'hard') then
      v_difficulty := 'medium';
    end if;

    v_language := coalesce(v_item->>'language', 'en');
    if v_language not in ('en', 'hi', 'hinglish') then
      v_language := 'en';
    end if;

    v_question_type := coalesce(v_item->>'question_type', v_item->>'questionType', 'mcq');
    v_source := coalesce(v_item->>'source', p_source, 'upload');

    -- Resolve chapter and subject display names if missing
    v_chapter := coalesce(v_item->>'chapter', '');
    if v_chapter = '' and v_chapter_id is not null then
      select coalesce(ct.title, c.chapter_key) into v_chapter
      from public.chapters c
      left join public.chapter_translations ct on ct.chapter_id = c.id and ct.language = 'en'
      where c.id = v_chapter_id
      limit 1;
    end if;

    v_subject_name := coalesce(v_item->>'subject_name', v_item->>'subjectName', '');
    if v_subject_name = '' and v_subject_id is not null then
      select coalesce(st.name, s.slug) into v_subject_name
      from public.subjects s
      left join public.subject_translations st on st.subject_id = s.id and st.language = 'en'
      where s.id = v_subject_id
      limit 1;
    end if;

    -- Insert row into public.question_bank
    insert into public.question_bank (
      question,
      options,
      correct_option,
      explanation,
      subject_id,
      subject_name,
      chapter,
      chapter_id,
      topic_id,
      difficulty,
      language,
      question_type,
      source,
      created_by,
      status,
      times_used,
      created_at,
      updated_at
    ) values (
      v_question,
      v_formatted_options,
      v_correct_opt,
      v_explanation,
      v_subject_id,
      coalesce(v_subject_name, ''),
      coalesce(v_chapter, ''),
      v_chapter_id,
      v_topic_id,
      v_difficulty,
      v_language,
      v_question_type,
      v_source,
      v_uid,
      v_target_status,
      0,
      now(),
      now()
    ) returning id into v_new_id;

    v_saved_ids := array_append(v_saved_ids, v_new_id);
  end loop;

  return jsonb_build_object(
    'total', jsonb_array_length(p_drafts),
    'saved_count', coalesce(array_length(v_saved_ids, 1), 0),
    'saved_ids', to_jsonb(v_saved_ids),
    'skipped_duplicate_count', jsonb_array_length(v_skipped),
    'skipped_duplicates', v_skipped
  );
end;
$$;

REVOKE ALL ON FUNCTION public.rpc_save_drafts_to_question_bank(jsonb, uuid, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_save_drafts_to_question_bank(jsonb, uuid, uuid, text, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- VERIFICATION / POSTFLIGHT QUERIES (read-only)
-- ============================================================================
-- 1. Verify is_ephemeral column exists:
-- SELECT column_name, data_type, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'uploaded_documents'
--   AND column_name = 'is_ephemeral';
-- expect: is_ephemeral | boolean | true | NO
--
-- 2. Verify functions exist and have secure search_path and execution grants:
-- SELECT p.proname, p.prosecdef, p.proconfig,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname IN ('rpc_purge_ephemeral_documents', 'rpc_save_drafts_to_question_bank');
-- expect: prosecdef=true, proconfig={search_path=}, anon_exec=false, auth_exec=true
-- ============================================================================
