import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown after a successful submission of a group test whose result isn't
/// published yet (`rpc_submit_and_score_test`'s `result_published: false`
/// — the caller's own score/leaderboard entry stays hidden by the live
/// `own results`/`rpc_get_leaderboard` publish gate until the group's
/// cohort leader explicitly publishes it). Never shows a score or any
/// partial result here — the server withholds `answers` entirely in this
/// case, so there is nothing to show but this honest holding state.
class SubmissionPendingScreen extends StatelessWidget {
  const SubmissionPendingScreen({this.testId, super.key});

  final String? testId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Submission Received')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.hourglass_top_rounded,
                  size: 34,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your test has been submitted',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Results will be published by the group leader once everyone '
                'has finished. You\'ll be notified as soon as they\'re available.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('submission_pending_done_btn'),
                onPressed: () => context.go('/tests'),
                child: const Text('Back to Tests'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
