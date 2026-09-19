-- G12 POSTCHECK: Verify no new backend objects were created.
-- G12 is entirely frontend — the leaderboard derives from existing results.

-- 1. No new tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name LIKE '%leaderboard%';

-- 2. No new RPCs
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%leaderboard%';

-- 3. No new views
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name LIKE '%leaderboard%';

-- 4. Confirm the results table still has all required columns
SELECT
  count(*) AS required_columns_present
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'results'
  AND column_name IN (
    'attempt_id', 'test_id', 'user_id',
    'score', 'max_score', 'percentage', 'accuracy',
    'correct_count', 'wrong_count', 'unanswered_count',
    'rank', 'computed_at'
  );

-- Expected: 12

SELECT 'G12 postcheck complete — no backend objects created.' AS status;
