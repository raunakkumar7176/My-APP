import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/profile_service.dart';
import '../state/results_controller.dart';
import '../widgets/question_review_card.dart';

/// Post-submission review by attempt id: safe questions + the user's own
/// answers, plus the real correct option via `rpc_get_my_answer_key`
/// (migration 0079) — which only ever reveals it for the caller's own
/// already-submitted attempt, never mid-test or for someone else's.
class QuestionReviewScreen extends StatefulWidget {
  const QuestionReviewScreen({
    required this.attemptId,
    this.controller,
    super.key,
  });

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

  Future<void> _downloadQuestionPaper() async {
    try {
      final bytes = await _c.buildQuestionPaperPdf();
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${_c.test?.title ?? 'test'} - question paper.pdf',
      );
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  static String _studentName() {
    final profile = ProfileService.currentProfile?.fullName.trim();
    if (profile != null && profile.isNotEmpty) return profile;
    return AuthService.currentUser?.email ?? 'Student';
  }

  Future<void> _downloadAnswerSheet() async {
    try {
      final bytes = await _c.buildAnswerSheetPdf(studentName: _studentName());
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${_c.test?.title ?? 'test'} - answer sheet.pdf',
      );
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
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
        actions: [
          // Question paper for the student, from the already-loaded safe
          // questions (post-submission; never contains the answer key).
          if (_c.reviewLoaded && _c.questions.isNotEmpty) ...[
            IconButton(
              key: const Key('download_answer_sheet'),
              tooltip: 'Download answer sheet',
              icon: const Icon(Icons.grid_on_outlined),
              onPressed: _downloadAnswerSheet,
            ),
            IconButton(
              tooltip: 'Download question paper',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _downloadQuestionPaper,
            ),
          ],
        ],
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
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.error,
                    ),
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
              itemCount: _c.questions.length + (_c.answersLoadFailed ? 1 : 0),
              itemBuilder: (context, index) {
                if (_c.answersLoadFailed && index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      leading: Icon(Icons.info_outline, size: 20),
                      content: Text(
                        'Your selections could not be loaded; '
                        'scoring was done on the server.',
                      ),
                      actions: [SizedBox.shrink()],
                    ),
                  );
                }
                final i = _c.answersLoadFailed ? index - 1 : index;
                final q = _c.questions[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: QuestionReviewCard(
                    question: q,
                    answer: _c.answerFor(q.id),
                    questionNumber: i + 1,
                    totalQuestions: _c.questions.length,
                    correctOption: _c.correctOptionFor(q.id),
                  ),
                );
              },
            ),
    );
  }
}
