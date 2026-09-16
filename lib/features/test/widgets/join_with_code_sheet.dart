import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test.dart';
import '../../../core/services/attempt_service.dart';
import '../../../core/services/question_service.dart';
import '../../../core/services/test_service.dart';

/// "Challenge with Friends" entry by access/join code.
///
/// Flow (all server-authoritative):
///   rpc_start_attempt_by_code(code)  → attempt (+ optional test_title)
///   tests row via getTestById        → may be unreadable for a non-member;
///                                      falls back to a minimal Test
///   get_test_questions_safe(test, code) → questions (never the answer key)
///   → /test-taking
class JoinWithCodeSheet extends StatefulWidget {
  const JoinWithCodeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const JoinWithCodeSheet(),
    );
  }

  /// Builds the `Test` handed to the taking/result screens when the coded
  /// test's row cannot be read by this user. Only `id`, `title` and
  /// `shuffleQuestions` are consumed downstream.
  @visibleForTesting
  static Test fallbackTest({required String testId, String? title}) {
    return Test(
      id: testId,
      createdBy: '',
      title: (title == null || title.trim().isEmpty)
          ? 'Challenge with Friends'
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

  Future<void> _join() async {
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
      final joined = await AttemptService.joinByCode(code);
      final attempt = joined.attempt;

      Test? test;
      try {
        test = await TestService.getTestById(attempt.testId);
      } catch (e) {
        AppLogger.warning('Coded test row not readable, using fallback: $e');
      }
      test ??= JoinWithCodeSheet.fallbackTest(
        testId: attempt.testId,
        title: joined.testTitle,
      );

      final questions = await QuestionService.getQuestionsSafe(
        testId: attempt.testId,
        accessCode: code,
      );

      if (!mounted) return;
      // Grab the router before the sheet's context is popped.
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go('/test-taking', extra: {
        'attempt': attempt,
        'questions': questions,
        'test': test,
      });
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
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
          Text(
            'Join with code',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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
