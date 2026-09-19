-- G12 PRECHECK: Verify the live schema supports the leaderboard.
-- No new objects are created. This confirms the existing `results` table
-- has the columns the leaderboard reads under RLS.

-- 1. results columns needed for the leaderboard
SELECT
  column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'results'
  AND column_name IN (
    'attempt_id', 'test_id', 'user_id',
    'score', 'max_score', 'percentage', 'accuracy',
    'correct_count', 'wrong_count', 'unanswered_count',
    'rank', 'computed_at'
  )
ORDER BY column_name;

-- 2. result_batches exists (batch status check in the results screen)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'result_batches'
) AS result_batches_exists;

-- 3. No new objects should be created by G12.
SELECT 'G12 precheck complete — all data comes from existing results rows.' AS status;
