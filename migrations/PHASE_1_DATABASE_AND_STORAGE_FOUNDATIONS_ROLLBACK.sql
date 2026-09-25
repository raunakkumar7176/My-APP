-- ============================================================================
-- Phase 1 — Database & Storage Foundations: ROLLBACK SCRIPT
-- My Preparation — Flutter + Supabase
--
-- PURPOSE:
-- Safely reverts the objects created in PHASE_1_DATABASE_AND_STORAGE_FOUNDATIONS.sql:
-- 1. Drops rpc_save_drafts_to_question_bank
-- 2. Drops rpc_purge_ephemeral_documents
-- 3. Drops index idx_uploaded_documents_ephemeral_purge
-- 4. Removes is_ephemeral column from public.uploaded_documents
-- ============================================================================

BEGIN;

-- 1. Drop Question Bank Save Bridge RPC
DROP FUNCTION IF EXISTS public.rpc_save_drafts_to_question_bank(jsonb, uuid, uuid, text, text);

-- 2. Drop Ephemeral Storage Purge Routine RPC
DROP FUNCTION IF EXISTS public.rpc_purge_ephemeral_documents(uuid, integer);

-- 3. Drop Ephemeral Index
DROP INDEX IF EXISTS public.idx_uploaded_documents_ephemeral_purge;

-- 4. Drop is_ephemeral Column
ALTER TABLE public.uploaded_documents
  DROP COLUMN IF EXISTS is_ephemeral;

NOTIFY pgrst, 'reload schema';

COMMIT;
