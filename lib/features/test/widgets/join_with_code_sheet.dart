import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test.dart';
import '../data/attempt_repository.dart';
import '../data/question_repository.dart';
import '../data/test_repository.dart';
import '../domain/test_kind.dart';
import '../state/attempt_launch_store.dart';

/// "Challenge with Friends" entry by access/join code.
///
/// Flow (all server-authoritative):
///   rpc_start_attempt_by_code(code)  → attempt (+ optional test_title)
///   tests row via TestRepository     → may be unreadable for a non-member;
///                                      falls back to a minimal Test
///   get_test_questions_safe(test, code) → questions (never the answer key)
///   → /attempts/:id/take?test=…&code=…  (ids only; launch handed over in memory)
class JoinWithCodeSheet extends StatefulWidget {
  const JoinWithCodeSheet({
    this.attempts = const SupabaseAttemptRepository(),
    this.questions = const SupabaseQuestionRepository(),
    this.tests = const SupabaseTestRepository(),
    super.key,
  });

  final AttemptRepository attempts;
  final QuestionRepository questions;
  final TestRepository tests;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const JoinWithCodeSheet(),
    );
  }

  /// The `Test` handed to the taking/result screens when the coded test's
  /// row cannot be read by this user. Only `id`, `title` and
  /// `shuffleQuestions` are consumed downstream.
  @visibleForTesting
  static Test fallbackTest({required String testId, String? title}) {
    return Test(
      id: testId,
      createdBy: '',
      title: (title == null || title.trim().isEmpty)
          ? TestKind.challengeWithFriends.label
          : title.trim(),
      status: TestStatus.live,
      testMode: 'live',
    );
  }

  @override
  State<JoinWithCodeSheet> createState() => _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends State<JoinWithCodeSheet> {
  final _controller = TextEditingController();
  bool _isJoining = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The server answers ATTEMPT_ALREADY_COMPLETED when this user already
  /// finished the coded test; only after an explicit confirmation is the
  /// call repeated with reattempt = true (the server still enforces the
  /// limit and may answer REATTEMPT_LIMIT_REACHED).
  static const alreadyCompletedMessage =
      'You have already completed this test. Use Re-attempt to try again.';

  Future<bool?> _confirmReattempt() => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Re-attempt this test?'),
      content: const Text(
        'You have already completed this test. Start a new attempt? '
        'Your previous results are kept.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Re-attempt'),
        ),
      ],
    ),
  );

  Future<void> _join({bool reattempt = false}) async {
    if (_isJoining) return;
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a test code.');
      return;
    }
    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final started = await widget.attempts.startByCode(
        code,
        reattempt: reattempt,
      );
      final attempt = started.attempt;

      Test? test;
      try {
        test = await widget.tests.getById(attempt.testId);
      } catch (e) {
        AppLogger.warning('Coded test row not readable, using fallback: $e');
      }
      test ??= JoinWithCodeSheet.fallbackTest(
        testId: attempt.testId,
        title: started.testTitle,
      );

      final questions = await widget.questions.safeQuestions(
        attempt.testId,
        accessCode: code,
      );

      if (!mounted) return;
      AttemptLaunchStore.putLaunch(
        started: started,
        questions: questions,
        test: test,
      );
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go(
        '/attempts/${attempt.id}/take?test=${attempt.testId}&code=${Uri.encodeQueryComponent(code)}',
      );
    } on AppError catch (e) {
      if (!mounted) return;
      if (!reattempt && e.message == alreadyCompletedMessage) {
        setState(() => _isJoining = false);
        final again = await _confirmReattempt();
        if (again == true && mounted) await _join(reattempt: true);
        return;
      }
      setState(() => _error = e.message);
    } catch (e) {
      AppLogger.error('Join with code unexpected: $e');
      if (mounted) {
        setState(() => _error = 'Could not join the test. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Join with code', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Enter the code shared by the test creator.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isJoining,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Test code',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isJoining ? null : _join,
              icon: _isJoining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_isJoining ? 'Joining...' : 'Join'),
            ),
          ),
        ],
      ),
    );
  }
}
