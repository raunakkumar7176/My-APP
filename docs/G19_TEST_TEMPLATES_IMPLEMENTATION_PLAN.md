# G19 Test Templates V1 — Implementation Plan

## Overview

Implement a reusable test template system that allows authorized users to save test configurations as templates and create new independent tests from those templates.

## Architecture Decisions

### Template Entity
A template stores a **test configuration snapshot**, NOT a live test. The key fields:

| Column | Type | Description |
|---|---|---|
| `id` | uuid | Primary key |
| `created_by` | uuid | Owner (references profiles) |
| `group_id` | uuid (nullable) | Optional group association |
| `title` | text | Template name |
| `description` | text | Optional description |
| `configuration` | jsonb | Test configuration snapshot |
| `created_at` | timestamptz | Creation timestamp |
| `updated_at` | timestamptz | Last update timestamp |

### Configuration JSONB Structure
Stores the test creation configuration:
```json
{
  "kind": "practice",
  "duration_sec": 3600,
  "marks_per_question": 1.0,
  "negative_marks": 0.25,
  "test_mode": "self",
  "settings": { ... },
  "attempt_settings": { "allow_reattempt": true, "max_attempts": 3 },
  "late_join": { "enabled": false, "minutes": 10 },
  "question_config": { "total": 20, "easy": 7, "medium": 7, "hard": 6 }
}
```

**Why JSONB?** The existing `tests.settings` is already JSONB. Reusing this pattern:
- Avoids duplicating 10+ columns
- Preserves all configuration keys without schema changes
- Round-trips cleanly with existing `BackendMapping` and `TestCreationController`

### Security Model
- **Personal templates**: Owner-only access (SELECT/UPDATE/DELETE WHERE created_by = auth.uid())
- **Group templates**: Group members can read; owner/leaders can CRUD
- Server-side RLS policies enforce access (UI hiding is NOT security)
- No new roles; reuse existing `CREATE_TEST`/`EDIT_TEST` permissions for group templates

### Template → Test Flow
1. User clicks "Use Template" on a template
2. Template configuration is loaded into `TestCreationController`
3. User can modify the configuration before creating the test
4. Creating a test produces an independent entity (template edits don't affect created tests)

## Files to Create/Modify

### New Files
1. `My-Prepration/supabase/migrations/0052_test_templates.sql` — Schema + RLS
2. `lib/core/models/test_template.dart` — Model
3. `lib/features/test/data/test_template_repository.dart` — Repository
4. `lib/features/test/state/test_template_controller.dart` — List controller
5. `lib/features/test/state/template_form_controller.dart` — Create/edit controller
6. `lib/features/test/screens/template_listing_screen.dart` — Template list UI
7. `lib/features/test/screens/template_form_screen.dart` — Template form UI
8. `test/g19/fakes.dart` — Fake repository for tests
9. `test/g19/test_template_test.dart` — Tests

### Modified Files
1. `lib/app/app_router.dart` — Add template routes
2. `lib/features/test/state/test_creation_controller.dart` — Add `loadFromTemplate()` method
3. `lib/features/test/screens/test_listing_screen.dart` — Add templates tab/button
4. `lib/features/test/screens/test_creation_screen.dart` — Support template preloading

## Migration Design (0052)

```sql
-- Idempotent, reversible, RLS-protected
CREATE TABLE IF NOT EXISTS test_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID NOT NULL REFERENCES profiles(id),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  description TEXT NOT NULL DEFAULT '',
  configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS policies
ALTER TABLE test_templates ENABLE ROW LEVEL SECURITY;

-- Owner can CRUD their personal templates
CREATE POLICY "owner CRUD personal template"
  ON test_templates FOR ALL
  USING (created_by = auth.uid() AND group_id IS NULL);

-- Group members can read group templates
CREATE POLICY "member read group template"
  ON test_templates FOR SELECT
  USING (group_id IS NOT NULL AND fn_is_member(group_id, auth.uid()));

-- Group owner/leaders can manage group templates
CREATE POLICY "leader manage group template"
  ON test_templates FOR ALL
  USING (group_id IS NOT NULL AND fn_is_group_owner(group_id, auth.uid()));
```

## Test Plan

1. Create template (personal)
2. List templates (personal)
3. Edit template
4. Delete template
5. Unauthorized access (another user's template)
6. Use template → new test configuration
7. Editing template does not modify created test
8. Double-tap/single-flight protection
9. Error/retry handling
10. Group permission gate (group templates)
