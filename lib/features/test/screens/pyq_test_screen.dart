import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../data/pyq_repository.dart';
import '../domain/pyq_models.dart';

/// Timed, proctored-style run through a PYQ paper. Options carry no
/// correct-answer information from the server until [_submit] calls
/// rpc_submit_pyq_test — grading happens server-side.
class PyqTestScreen extends StatefulWidget {
  const PyqTestScreen({
    super.key,
    required this.examName,
    required this.examYear,
    this.examShift,
  });

  final String examName;
  final int examYear;
  final String? examShift;

  @override
  State<PyqTestScreen> createState() => _PyqTestScreenState();
}

class _PyqTestScreenState extends State<PyqTestScreen> {
  static const _secondsPerQuestion = 60;

  final _repo = const SupabasePyqRepository();
  List<PyqQuestion> _questions = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  int _index = 0;
  final Map<String, int?> _answers = {};
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final questions = await _repo.fetchTestQuestions(
        examName: widget.examName,
        examYear: widget.examYear,
        examShift: widget.examShift,
      );
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _isLoading = false;
        _secondsLeft = questions.length * _secondsPerQuestion;
      });
      _startTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load questions. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
        _submit();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  String get _timeLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    _timer?.cancel();
    setState(() => _isSubmitting = true);
    try {
      final answers = _questions
          .map((q) => (questionId: q.id, selectedOption: _answers[q.id]))
          .toList();
      final result = await _repo.submitTest(answers);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              _PyqResultScreen(result: result, questions: _questions),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit test?'),
            content: const Text('Your progress will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.examName} ${widget.examYear} · Test'),
          actions: [
            if (!_isLoading && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    _timeLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_questions.isEmpty) {
      return const Center(child: Text('No questions found for this paper.'));
    }

    final q = _questions[_index];
    final options = q.displayOptions(false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _questions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final answered = _answers.containsKey(_questions[i].id);
                final isCurrent = i == _index;
                return InkWell(
                  onTap: () => setState(() => _index = i),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: isCurrent
                        ? AppColors.primaryLight
                        : answered
                        ? AppColors.success.withValues(alpha: 0.2)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: isCurrent ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Question ${_index + 1} of ${_questions.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                AppSpacing.vGapSm,
                Text(
                  q.displayQuestion(false),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.vGapMd,
                for (var i = 0; i < options.length; i++)
                  _buildOption(q, i, options[i]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_index > 0)
                Expanded(
                  child: AppButton.secondary(
                    label: 'Previous',
                    onPressed: () => setState(() => _index--),
                  ),
                ),
              if (_index > 0) AppSpacing.hGapMd,
              Expanded(
                child: _index >= _questions.length - 1
                    ? AppButton.primary(
                        label: 'Submit',
                        isLoading: _isSubmitting,
                        onPressed: _submit,
                      )
                    : AppButton.primary(
                        label: 'Next',
                        onPressed: () => setState(() => _index++),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOption(PyqQuestion q, int i, String text) {
    final selected = _answers[q.id] == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.primaryContainerLight.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdBorder,
        child: InkWell(
          borderRadius: AppRadius.mdBorder,
          onTap: () => setState(() => _answers[q.id] = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? AppColors.primaryLight : null,
                ),
                AppSpacing.hGapSm,
                Expanded(child: Text(text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PyqResultScreen extends StatelessWidget {
  const _PyqResultScreen({required this.result, required this.questions});

  final PyqTestResult result;
  final List<PyqQuestion> questions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  '${result.scorePercentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                AppSpacing.vGapSm,
                Text('${result.correct} / ${result.total} correct'),
              ],
            ),
          ),
          AppSpacing.vGapLg,
          for (final r in result.results)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: r.isCorrect
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppRadius.mdBorder,
              ),
              child: Row(
                children: [
                  Icon(
                    r.isCorrect ? Icons.check_circle : Icons.cancel,
                    color: r.isCorrect ? AppColors.success : AppColors.error,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      questions
                          .firstWhere(
                            (q) => q.id == r.questionId,
                            orElse: () => questions.first,
                          )
                          .displayQuestion(false),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          AppSpacing.vGapLg,
          AppButton.primary(
            label: 'Done',
            isFullWidth: true,
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
    );
  }
}
