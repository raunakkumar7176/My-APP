import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../state/results_controller.dart';
import '../widgets/question_review_card.dart';

/// Post-submission review by attempt id: safe questions + the user's own
/// answers. Correct/incorrect per question is NOT shown — the backend does
/// not expose the answer key or per-question correctness, and the client
/// never fabricates it.
class QuestionReviewScreen extends StatefulWidget {
  const QuestionReviewScreen({required this.attemptId, this.controller, super.key});

  final String attemptId;
  final ResultsController? controller;

  @override
  State<QuestionReviewScreen> createState() => _QuestionReviewScreenState();
}

class _QuestionReviewScreenState extends State<QuestionReviewScreen> {
  late final ResultsController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? ResultsController(attemptId: widget.attemptId);
    _c.addListener(_onChanged);
    _init();
  }

  Future<void> _init() async {
    if (_c.result == null) await _c.load();
    await _c.loadReview();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _c.isLoading || (_c.isBusy && !_c.reviewLoaded);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Answers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/attempts/${widget.attemptId}/result'),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : _c.error != null && !_c.reviewLoaded
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_c.error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _init, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _c.questions.length + (_c.answersUnreadable ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_c.answersUnreadable && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: MaterialBanner(
                          leading: Icon(Icons.info_outline, size: 20),
                          content: Text(
                            'Your selections cannot be shown on this backend yet; '
                            'scoring was done on the server.',
                          ),
                          actions: [SizedBox.shrink()],
                        ),
                      );
                    }
                    final i = _c.answersUnreadable ? index - 1 : index;
                    final q = _c.questions[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: QuestionReviewCard(
                        question: q,
                        answer: _c.answerFor(q.id),
                        questionNumber: i + 1,
                        totalQuestions: _c.questions.length,
                      ),
                    );
                  },
                ),
    );
  }
}
