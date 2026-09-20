import 'package:flutter/material.dart';

import '../../../core/models/question_bank_item.dart';

/// Bottom sheet for filtering question bank items.
class QuestionBankFilterSheet extends StatefulWidget {
  const QuestionBankFilterSheet({
    required this.currentFilter,
    required this.onApply,
    super.key,
  });

  final QuestionBankFilter currentFilter;
  final ValueChanged<QuestionBankFilter> onApply;

  @override
  State<QuestionBankFilterSheet> createState() =>
      _QuestionBankFilterSheetState();
}

class _QuestionBankFilterSheetState extends State<QuestionBankFilterSheet> {
  late String? _status;
  late String? _difficulty;
  late String? _language;
  late String? _questionType;
  late String? _source;

  @override
  void initState() {
    super.initState();
    _status = widget.currentFilter.status;
    _difficulty = widget.currentFilter.difficulty;
    _language = widget.currentFilter.language;
    _questionType = widget.currentFilter.questionType;
    _source = widget.currentFilter.source;
  }

  void _apply() {
    widget.onApply(
      widget.currentFilter.copyWith(
        status: _status,
        difficulty: _difficulty,
        language: _language,
        questionType: _questionType,
        source: _source,
      ),
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    setState(() {
      _status = null;
      _difficulty = null;
      _language = null;
      _questionType = null;
      _source = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChanges = _status != widget.currentFilter.status ||
        _difficulty != widget.currentFilter.difficulty ||
        _language != widget.currentFilter.language ||
        _questionType != widget.currentFilter.questionType ||
        _source != widget.currentFilter.source;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Text(
                    'Filter Questions',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (hasChanges)
                    TextButton(
                      onPressed: _clear,
                      child: const Text('Clear All'),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Filter options
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Status filter
                    _FilterSection(
                      title: 'Status',
                      options: const [
                        'pending_review',
                        'approved',
                        'archived',
                        'needs_revision',
                      ],
                      selected: _status,
                      onChanged: (value) => setState(() => _status = value),
                    ),
                    const SizedBox(height: 16),

                    // Difficulty filter
                    _FilterSection(
                      title: 'Difficulty',
                      options: const [
                        'easy',
                        'medium',
                        'hard',
                        'mixed',
                      ],
                      selected: _difficulty,
                      onChanged: (value) => setState(() => _difficulty = value),
                    ),
                    const SizedBox(height: 16),

                    // Language filter
                    _FilterSection(
                      title: 'Language',
                      options: const [
                        'en',
                        'hi',
                        'hinglish',
                      ],
                      selected: _language,
                      onChanged: (value) => setState(() => _language = value),
                    ),
                    const SizedBox(height: 16),

                    // Question type filter
                    _FilterSection(
                      title: 'Question Type',
                      options: const [
                        'mcq',
                        'tf',
                        'short',
                        'num',
                      ],
                      selected: _questionType,
                      onChanged: (value) =>
                          setState(() => _questionType = value),
                    ),
                    const SizedBox(height: 16),

                    // Source filter
                    _FilterSection(
                      title: 'Source',
                      options: const [
                        'manual',
                        'ai',
                        'upload',
                      ],
                      selected: _source,
                      onChanged: (value) => setState(() => _source = value),
                    ),
                  ],
                ),
              ),

              // Apply button
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: hasChanges ? _apply : null,
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Section for a single filter option.
class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final option in options)
              FilterChip(
                label: Text(option.replaceAll('_', ' ')),
                selected: selected == option,
                onSelected: (_) =>
                    onChanged(selected == option ? null : option),
              ),
          ],
        ),
      ],
    );
  }
}
