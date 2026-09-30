import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../data/pyq_repository.dart';
import '../domain/pyq_models.dart';

/// Untimed practice run through a PYQ paper: submitting an option
/// immediately reveals green/red feedback + bilingual explanation.
class PyqPracticeScreen extends StatefulWidget {
  const PyqPracticeScreen({
    super.key,
    required this.examName,
    required this.examYear,
    this.examShift,
  });

  final String examName;
  final int examYear;
  final String? examShift;

  @override
  State<PyqPracticeScreen> createState() => _PyqPracticeScreenState();
}

class _PyqPracticeScreenState extends State<PyqPracticeScreen> {
  final _repo = const SupabasePyqRepository();
  List<PyqQuestion> _questions = [];
  bool _isLoading = true;
  String? _error;
  int _index = 0;
  int? _selectedOption;
  bool _revealed = false;
  final Map<String, int?> _attempted = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final questions = await _repo.fetchPracticeQuestions(
        examName: widget.examName,
        examYear: widget.examYear,
        examShift: widget.examShift,
      );
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load questions. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _selectOption(int optionIndex) {
    if (_revealed) return;
    setState(() {
      _selectedOption = optionIndex;
      _revealed = true;
      _attempted[_questions[_index].id] = optionIndex;
    });
  }

  void _next() {
    if (_index >= _questions.length - 1) return;
    setState(() {
      _index++;
      _selectedOption = _attempted[_questions[_index].id];
      _revealed = _selectedOption != null;
    });
  }

  void _previous() {
    if (_index <= 0) return;
    setState(() {
      _index--;
      _selectedOption = _attempted[_questions[_index].id];
      _revealed = _selectedOption != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.examName} ${widget.examYear} · Practice')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              AppSpacing.vGapMd,
              Text(_error!, textAlign: TextAlign.center),
              AppSpacing.vGapMd,
              AppButton.primary(label: 'Retry', onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _load();
              }),
            ],
          ),
        ),
      );
    }
    if (_questions.isEmpty) {
      return const Center(child: Text('No questions found for this paper.'));
    }

    final q = _questions[_index];
    final options = q.displayOptions(false);

    return Column(
      children: [
        LinearProgressIndicator(value: (_index + 1) / _questions.length, minHeight: 4),
        Expanded(
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Question ${_index + 1} of ${_questions.length}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
                ),
                AppSpacing.vGapSm,
                Text(
                  q.displayQuestion(false),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                AppSpacing.vGapMd,
                for (var i = 0; i < options.length; i++) _buildOption(q, i, options[i]),
                if (_revealed && (q.displayExplanation(false)?.isNotEmpty ?? false)) ...[
                  AppSpacing.vGapMd,
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainerLight.withValues(alpha: 0.3),
                      borderRadius: AppRadius.mdBorder,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Explanation', style: TextStyle(fontWeight: FontWeight.w700)),
                        AppSpacing.vGapXs,
                        Text(q.displayExplanation(false)!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_index > 0)
                Expanded(child: AppButton.secondary(label: 'Previous', onPressed: _previous)),
              if (_index > 0) AppSpacing.hGapMd,
              Expanded(
                child: AppButton.primary(
                  label: _index >= _questions.length - 1 ? 'Finish' : 'Next',
                  onPressed: _index >= _questions.length - 1
                      ? () => Navigator.of(context).pop()
                      : _next,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOption(PyqQuestion q, int i, String text) {
    Color? tileColor;
    IconData? trailingIcon;
    Color? trailingColor;

    if (_revealed) {
      if (q.correctOption == i) {
        tileColor = AppColors.success.withValues(alpha: 0.12);
        trailingIcon = Icons.check_circle;
        trailingColor = AppColors.success;
      } else if (_selectedOption == i) {
        tileColor = AppColors.error.withValues(alpha: 0.12);
        trailingIcon = Icons.cancel;
        trailingColor = AppColors.error;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tileColor ?? Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdBorder,
        child: InkWell(
          borderRadius: AppRadius.mdBorder,
          onTap: () => _selectOption(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(text)),
                if (trailingIcon != null) Icon(trailingIcon, color: trailingColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
