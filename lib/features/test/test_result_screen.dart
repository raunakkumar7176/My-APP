import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/errors/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/answer.dart';
import '../../core/models/question.dart';
import '../../core/models/result.dart';
import '../../core/models/result_analytics.dart';
import '../../core/models/self_reflection.dart';
import '../../core/models/test.dart';
import '../../core/services/attempt_service.dart';
import '../../core/services/question_service.dart';
import '../../core/services/result_service.dart';
import 'widgets/difficulty_analysis_extended_card.dart';
import 'widgets/mistake_summary_card.dart';
import 'widgets/result_history_card.dart';
import 'widgets/subject_analysis_card.dart';
import 'widgets/topic_analysis_card.dart';

class TestResultScreen extends StatefulWidget {
  const TestResultScreen({
    required this.result,
    required this.test,
    required this.questions,
    required this.answers,
    this.selfReflection,
    this.allResults,
    super.key,
  });

  final Result result;
  final Test test;
  final List<Question> questions;
  final Map<String, Answer> answers;
  final SelfReflection? selfReflection;
  final List<Result>? allResults;

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  List<SubjectBreakdownItem> _subjectItems = [];
  List<TopicBreakdownItem> _topicItems = [];
  List<Result> _allResults = [];
  bool _isLoadingAnalytics = true;
  bool _isRepeating = false;
  String? _analyticsError;

  @override
  void initState() {
    super.initState();
    _allResults = widget.allResults ?? [widget.result];
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      final futures = await Future.wait([
        ResultService.parseSubjectBreakdown(widget.result.subjectBreakdown),
        ResultService.getResultsForTest(widget.test.id)
            .catchError((_) => <Result>[]),
      ]);
      final subjects = futures[0] as List<SubjectBreakdownItem>;
      final topics = ResultService.parseTopicBreakdown(
        widget.result.topicBreakdown,
      );
      final allResults = futures[1] as List<Result>;

      if (mounted) {
        setState(() {
          _subjectItems = subjects;
          _topicItems = topics;
          _allResults = allResults.isNotEmpty ? allResults : [widget.result];
          _isLoadingAnalytics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAnalytics = false;
          _analyticsError = 'Failed to load analytics.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tests'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTestHeader(context),
            const SizedBox(height: 16),
            _buildScoreCard(context, result),
            const SizedBox(height: 16),
            _buildStatsGrid(context, result),
            const SizedBox(height: 16),
            _buildImprovementIndicator(context, result),
            if (_isLoadingAnalytics) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_analyticsError != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _analyticsError!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ),
            ],
            if (!_isLoadingAnalytics && _analyticsError == null) ...[
              const SizedBox(height: 16),
              SubjectAnalysisCard(items: _subjectItems),
              const SizedBox(height: 16),
              TopicAnalysisCard(items: _topicItems),
              const SizedBox(height: 16),
              _buildDifficultyAnalysis(context, result),
            ],
            const SizedBox(height: 16),
            _buildMistakeSummary(context, result),
            const SizedBox(height: 16),
            ResultHistoryCard(results: _allResults, currentResultId: result.id),
            if (widget.selfReflection != null) ...[
              const SizedBox(height: 16),
              _buildReflectionComparison(context, result),
            ],
            const SizedBox(height: 16),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTestHeader(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.test.title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (widget.result.computedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Completed ${_formatDateTime(widget.result.computedAt!)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondaryLight),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard(BuildContext context, Result result) {
    final percentage = result.percentage ?? 0;
    final isPassed = result.isPassed ?? false;

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: percentage / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        isPassed ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPassed ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: (isPassed ? AppColors.success : AppColors.error)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isPassed ? 'PASSED' : 'NOT PASSED',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isPassed ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (result.score != null && result.maxScore != null) ...[
              const SizedBox(height: 8),
              Text(
                '${result.score!.toStringAsFixed(1)} / ${result.maxScore!.toStringAsFixed(1)} marks',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryLight),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, Result result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Summary',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statItem(
                    context,
                    label: 'Correct',
                    value: '${result.correctCount ?? 0}',
                    color: AppColors.success,
                  ),
                ),
                Expanded(
                  child: _statItem(
                    context,
                    label: 'Wrong',
                    value: '${result.wrongCount ?? 0}',
                    color: AppColors.error,
                  ),
                ),
                Expanded(
                  child: _statItem(
                    context,
                    label: 'Unanswered',
                    value: '${result.unansweredCount ?? 0}',
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statItem(
                    context,
                    label: 'Accuracy',
                    value: result.accuracy != null
                        ? '${result.accuracy!.toStringAsFixed(1)}%'
                        : '--',
                    color: AppColors.primaryLight,
                  ),
                ),
                Expanded(
                  child: _statItem(
                    context,
                    label: 'Total',
                    value: '${result.totalQuestions ?? 0}',
                    color: AppColors.textPrimaryLight,
                  ),
                ),
                Expanded(
                  child: _statItem(
                    context,
                    label: 'Rank',
                    value: result.rank != null ? '#${result.rank}' : '--',
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.textSecondaryLight),
        ),
      ],
    );
  }

  Widget _buildImprovementIndicator(BuildContext context, Result result) {
    if (_allResults.length < 2) {
      return const SizedBox.shrink();
    }
    final previous = ResultService.getPreviousResult(
      allResults: _allResults,
      currentResultId: result.id,
    );
    if (previous == null) return const SizedBox.shrink();

    final currentPct = result.percentage ?? 0;
    final previousPct = previous.percentage ?? 0;
    final diff = currentPct - previousPct;

    String text;
    Color color;
    if (diff > 0.5) {
      text = 'Improved by ${diff.toStringAsFixed(1)} percentage points';
      color = AppColors.success;
    } else if (diff < -0.5) {
      text = 'Lower by ${diff.abs().toStringAsFixed(1)} percentage points';
      color = AppColors.error;
    } else {
      text = 'Same percentage as previous attempt';
      color = AppColors.textSecondaryLight;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              diff > 0.5
                  ? Icons.trending_up
                  : diff < -0.5
                  ? Icons.trending_down
                  : Icons.trending_flat,
              color: color,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comparison with Previous Attempt',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondaryLight),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyAnalysis(BuildContext context, Result result) {
    return const DifficultyAnalysisExtendedCard(items: []);
  }

  Widget _buildMistakeSummary(BuildContext context, Result result) {
    final wrongCount = result.wrongCount ?? 0;
    final unansweredCount = result.unansweredCount ?? 0;
    final accuracy = result.accuracy;

    final mistakesBySubject = <String, int>{};
    final mistakesByDifficulty = <String, int>{};

    for (final q in widget.questions) {
      final answer = widget.answers[q.id];
      final isAnswered =
          answer != null &&
          (answer.isAnswered || answer.selectedOptionId != null);
      if (isAnswered) continue;

      final subject = q.subjectId ?? 'Unknown';
      mistakesBySubject[subject] = (mistakesBySubject[subject] ?? 0) + 1;

      final difficulty = q.difficulty.name;
      mistakesByDifficulty[difficulty] =
          (mistakesByDifficulty[difficulty] ?? 0) + 1;
    }

    return MistakeSummaryCard(
      totalMistakes: wrongCount,
      totalUnanswered: unansweredCount,
      accuracy: accuracy ?? 0,
      mistakesBySubject: mistakesBySubject,
      mistakesByDifficulty: mistakesByDifficulty,
      onReviewMistakes: unansweredCount > 0
          ? () => _openUnansweredReview(context)
          : null,
    );
  }

  Widget _buildReflectionComparison(BuildContext context, Result result) {
    final reflection = widget.selfReflection!;
    final actualPercentage = result.percentage ?? 0;
    final expectedMidpoint = reflection.expectedMidpoint;
    final difference = actualPercentage - expectedMidpoint;

    String relation;
    if (actualPercentage >= reflection.expectedMidpoint - 10 &&
        actualPercentage <= reflection.expectedMidpoint + 10) {
      relation = 'Within expected range';
    } else if (actualPercentage > reflection.expectedMidpoint + 10) {
      relation = 'Above expected range';
    } else {
      relation = 'Below expected range';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expectation vs Actual',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _comparisonRow(
              context,
              label: 'Confidence',
              value: reflection.confidenceLabel,
            ),
            _comparisonRow(
              context,
              label: 'Expected',
              value: reflection.expectedRangeLabel,
            ),
            _comparisonRow(
              context,
              label: 'Actual',
              value: '${actualPercentage.toStringAsFixed(1)}%',
              valueColor: AppColors.primaryLight,
            ),
            _comparisonRow(
              context,
              label: 'Difference',
              value:
                  '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(1)}%',
              valueColor: difference >= 0 ? AppColors.success : AppColors.error,
            ),
            _comparisonRow(context, label: 'Relation', value: relation),
            if (reflection.optionalReflection != null) ...[
              const Divider(height: 20),
              Text(
                'Your reflection:',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondaryLight),
              ),
              const SizedBox(height: 4),
              Text(
                reflection.optionalReflection!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _comparisonRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openReview(context),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Review Questions'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (widget.result.unansweredCount ?? 0) > 0
                    ? () => _openUnansweredReview(context)
                    : null,
                icon: const Icon(Icons.help_outline),
                label: const Text('Review Unanswered'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isRepeating ? null : () => _repeatTest(context),
                icon: _isRepeating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.replay),
                label: Text(_isRepeating ? 'Starting...' : 'Repeat Test'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.go('/tests'),
                icon: const Icon(Icons.home),
                label: const Text('Back to Tests'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openReview(BuildContext context) {
    context.go(
      '/question-review',
      extra: {
        'test': widget.test,
        'questions': widget.questions,
        'answers': widget.answers,
        'result': widget.result,
      },
    );
  }

  void _openUnansweredReview(BuildContext context) {
    final unansweredIds = <String>{};
    for (final q in widget.questions) {
      final answer = widget.answers[q.id];
      final isAnswered =
          answer != null &&
          (answer.isAnswered || answer.selectedOptionId != null);
      if (!isAnswered) {
        unansweredIds.add(q.id);
      }
    }

    final filteredQuestions = widget.questions
        .where((q) => unansweredIds.contains(q.id))
        .toList();

    if (filteredQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unanswered questions to review.')),
      );
      return;
    }

    context.go(
      '/question-review',
      extra: {
        'test': widget.test,
        'questions': filteredQuestions,
        'answers': widget.answers,
        'result': widget.result,
      },
    );
  }

  Future<void> _repeatTest(BuildContext context) async {
    setState(() => _isRepeating = true);
    try {
      final attempt = await AttemptService.startAttempt(widget.test.id);
      if (!mounted) return;
      final questions = await QuestionService.getQuestionsSafe(
        testId: widget.test.id,
      );
      if (!mounted) return;
      context.go(
        '/test-taking',
        extra: {
          'attempt': attempt,
          'questions': questions,
          'test': widget.test,
        },
      );
    } on AppError catch (e) {
      if (mounted) {
        setState(() => _isRepeating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRepeating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start repeat test. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
