/// The single mapper from server error text to user-facing messages.
///
/// Server functions raise `CODE: detail` (e.g. `VALIDATION_ERROR: Test must
/// have at least one approved question to publish`, `TEST_CODE_INVALID`).
/// Match on the code first; fall back to a generic message that keeps the
/// server detail when it is short and printable, so real causes are not
/// hidden behind "Something went wrong".
abstract final class TestErrors {
  static String map(
    String raw, {
    TestErrorContext context = TestErrorContext.generic,
  }) {
    final lower = raw.toLowerCase();

    // ── auth / access ──
    if (lower.contains('not_authenticated') || lower.contains('jwt')) {
      return 'Your session has expired. Please log in again.';
    }
    if (lower.contains('test_access_denied') ||
        lower.contains('permission') ||
        lower.contains('denied') ||
        lower.contains('row-level security')) {
      return context == TestErrorContext.start
          ? 'You do not have access to this test.'
          : 'You do not have permission to perform this action.';
    }

    // ── codes ──
    if (lower.contains('test_code_invalid')) {
      return 'Invalid test code. Please check and try again.';
    }
    if (lower.contains('test_code_ambiguous')) {
      return 'This code matches more than one test. Ask the creator for the exact code.';
    }

    // ── lifecycle ──
    if (lower.contains('test_not_found') || lower.contains('not found')) {
      return 'Test not found.';
    }
    if (lower.contains('test_not_started')) {
      return 'This test has not started yet.';
    }
    if (lower.contains('test_not_available')) {
      return 'This test is not currently available.';
    }
    if (lower.contains('test_ended')) {
      return 'This test has ended.';
    }
    if (lower.contains('test_already_deleted')) {
      return 'This test has already been deleted.';
    }
    if (lower.contains('test_not_draft')) {
      return 'Only draft tests can be deleted.';
    }
    if (lower.contains('auth_required')) {
      return 'Your session has expired. Please log in again.';
    }
    if (lower.contains('test_full')) {
      return 'This test has reached its maximum number of participants.';
    }
    if (lower.contains('late_join_not_allowed')) {
      return 'This challenge has already started and does not allow late joining.';
    }
    if (lower.contains('attempt_not_found')) {
      return 'Attempt not found.';
    }
    if (lower.contains('attempt_already_submitted') ||
        lower.contains('already submitted')) {
      return 'This attempt has already been submitted.';
    }
    if (lower.contains('deadline')) {
      return 'The time limit for this attempt has passed.';
    }

    // ── publish validation (live message verified 2026-09-15) ──
    if (lower.contains('at least one approved') ||
        lower.contains('no approved question')) {
      return 'Approve all questions before publishing (Edit Test → Review → Approve).';
    }
    if (lower.contains('no questions')) {
      return 'Add at least one question before publishing.';
    }
    if (lower.contains('duplicate') || lower.contains('ordinal')) {
      return 'Fix duplicate question numbers before publishing.';
    }
    if (lower.contains('syllabus')) {
      return 'Fix syllabus references before publishing.';
    }
    if (lower.contains('group') && lower.contains('required')) {
      return 'Select a group for Group Test mode.';
    }
    if (lower.contains('duration')) {
      return 'Enter a valid duration for the test.';
    }
    if (lower.contains('validation_error')) {
      return _detail(raw) ??
          'The server rejected this request. Please review the test.';
    }

    // ── transport ──
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    }

    return _detail(raw) ?? _generic(context);
  }

  /// Short, printable server detail after a `CODE:` prefix, else null.
  static String? _detail(String raw) {
    final idx = raw.indexOf(':');
    final detail = (idx >= 0 ? raw.substring(idx + 1) : raw).trim();
    if (detail.isEmpty || detail.length > 140) return null;
    // Structured payloads / stack-like text are not user-facing.
    if (detail.contains('{') ||
        detail.contains('}') ||
        detail.contains('\n') ||
        detail.contains('"')) {
      return null;
    }
    return detail.endsWith('.') ? detail : '$detail.';
  }

  static String _generic(TestErrorContext c) {
    switch (c) {
      case TestErrorContext.publish:
        return 'Failed to publish test. Please try again.';
      case TestErrorContext.start:
        return 'Failed to start test. Please try again.';
      case TestErrorContext.save:
        return 'Failed to save. Please try again.';
      case TestErrorContext.submit:
        return 'Failed to submit. Please try again.';
      case TestErrorContext.load:
        return 'Failed to load. Please try again.';
      case TestErrorContext.delete:
        return 'Failed to delete test. Please try again.';
      case TestErrorContext.generic:
        return 'Something went wrong. Please try again.';
    }
  }
}

enum TestErrorContext { generic, publish, start, save, submit, load, delete }
