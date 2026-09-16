import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/models/answer.dart';
import '../../core/models/question.dart';
import '../../core/models/result.dart';
import '../../core/models/test.dart';
import 'widgets/question_review_card.dart';

class QuestionReviewScreen extends StatefulWidget {
  const QuestionReviewScreen({
    required this.test,
    required this.questions,
    required this.answers,
    required this.result,
    super.key,
  });

  final Test test;
  final List<Question> questions;
  final Map<String, Answer> answers;
  final Result result;

  @override
  State<QuestionReviewScreen> createState() => _QuestionReviewScreenState();
}

class _QuestionReviewScreenState extends State<QuestionReviewScreen> {
  int _currentPage = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.questions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Review'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/test-result', extra: {
            'test': widget.test,
            'questions': widget.questions,
            'answers': widget.answers,
            'result': widget.result,
          }),
        ),
      ),
      body: Column(
        children: [
          _buildSummaryBar(context),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: questions.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final q = questions[index];
                final answer = widget.answers[q.id];
                return QuestionReviewCard(
                  question: q,
                  answer: answer,
                  questionNumber: index + 1,
                  totalQuestions: questions.length,
                );
              },
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(BuildContext context) {
    final total = widget.questions.length;
    final answered = widget.answers.values
        .where((a) => a.isAnswered || a.selectedOptionId != null)
        .length;
    final unanswered = total - answered;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _chip(
              context,
              label: 'Answered',
              count: answered,
              color: AppColors.primaryLight,
            ),
            const SizedBox(width: 8),
            _chip(
              context,
              label: 'Unanswered',
              count: unanswered,
              color: AppColors.textSecondaryLight,
            ),
            const Spacer(),
            Text(
              '${_currentPage + 1} / $total',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondaryLight,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentPage > 0)
              TextButton.icon(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                  );
                },
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Prev'),
              ),
            const Spacer(),
            if (_currentPage < widget.questions.length - 1)
              TextButton.icon(
                onPressed: () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                  );
                },
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Next'),
                iconAlignment: IconAlignment.end,
              ),
            if (_currentPage >= widget.questions.length - 1)
              FilledButton(
                onPressed: () => context.go('/test-result', extra: {
                  'test': widget.test,
                  'questions': widget.questions,
                  'answers': widget.answers,
                  'result': widget.result,
                }),
                child: const Text('Done'),
              ),
          ],
        ),
      ),
    );
  }
}
