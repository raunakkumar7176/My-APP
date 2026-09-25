import 'package:flutter/material.dart';

import '../../../core/models/question.dart';
import '../models/question_draft.dart';

class QuestionEditor extends StatefulWidget {
  const QuestionEditor({this.initial, required this.onSave, super.key});

  final QuestionDraft? initial;
  final ValueChanged<QuestionDraft> onSave;

  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late final TextEditingController _questionController;
  late final TextEditingController _explanationController;
  late final TextEditingController _marksController;
  late final TextEditingController _negativeMarksController;
  late QuestionType _questionType;
  late DifficultyLevel _difficulty;
  late List<QuestionOptionDraft> _options;
  int? _correctOptionIndex;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _questionController = TextEditingController(
      text: initial?.questionText ?? '',
    );
    _explanationController = TextEditingController(
      text: initial?.explanation ?? '',
    );
    _marksController = TextEditingController(
      text: initial?.marks.toString() ?? '1',
    );
    _negativeMarksController = TextEditingController(
      text: initial?.negativeMarks?.toString() ?? '',
    );
    _questionType = initial?.questionType ?? QuestionType.mcqSingle;
    _difficulty = initial?.difficulty ?? DifficultyLevel.medium;
    _options = initial?.options.toList() ?? const [];
    // V1: every question needs >= 4 options; pad the editor to the minimum.
    while (_options.length < QuestionDraft.minOptions) {
      _options = [..._options, const QuestionOptionDraft(text: '')];
    }
    _correctOptionIndex = initial?.correctOptionIndex;
  }

  @override
  void dispose() {
    _questionController.dispose();
    _explanationController.dispose();
    _marksController.dispose();
    _negativeMarksController.dispose();
    super.dispose();
  }

  /// A question that already exists on the server. Its answer key is never
  /// sent to the client, so the editor opens with no correct option selected;
  /// leaving it unselected means "keep the stored answer".
  bool get _isServerQuestion => widget.initial?.id != null;

  bool get _isValid {
    if (_questionController.text.trim().isEmpty) return false;
    final marks = int.tryParse(_marksController.text);
    if (marks == null || marks <= 0) return false;
    if (_isMcqType) {
      if (_options.length < QuestionDraft.minOptions) return false;
      if (_options.any((o) => o.text.trim().isEmpty)) return false;
      if (_correctOptionIndex == null) return _isServerQuestion;
      if (_correctOptionIndex! < 0 || _correctOptionIndex! >= _options.length) {
        return false;
      }
    }
    return true;
  }

  bool get _isMcqType =>
      _questionType == QuestionType.mcqSingle ||
      _questionType == QuestionType.mcqMultiple;

  void _save() {
    setState(() => _showValidation = true);
    if (!_isValid) return;

    final draft = QuestionDraft(
      id: widget.initial?.id,
      questionText: _questionController.text.trim(),
      questionType: _questionType,
      options: _options,
      correctOptionIndex: _correctOptionIndex,
      explanation: _explanationController.text.trim().isEmpty
          ? null
          : _explanationController.text.trim(),
      difficulty: _difficulty,
      marks: int.parse(_marksController.text),
      negativeMarks: double.tryParse(_negativeMarksController.text),
      // Not editable here; carry them through so a server-question edit
      // does not drop them from local state.
      subjectId: widget.initial?.subjectId,
      topicNodeId: widget.initial?.topicNodeId,
      language: widget.initial?.language,
    );

    widget.onSave(draft);
  }

  void _addOption() {
    setState(() {
      _options = [..._options, const QuestionOptionDraft(text: '')];
    });
  }

  void _removeOption(int index) {
    if (_options.length <= QuestionDraft.minOptions) return;
    setState(() {
      _options = List.from(_options)..removeAt(index);
      if (_correctOptionIndex == index) {
        _correctOptionIndex = null;
      } else if (_correctOptionIndex != null && _correctOptionIndex! > index) {
        _correctOptionIndex = _correctOptionIndex! - 1;
      }
    });
  }

  void _updateOption(int index, String text) {
    setState(() {
      _options = _options.asMap().entries.map((entry) {
        if (entry.key == index) {
          return entry.value.copyWith(text: text);
        }
        return entry.value;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.initial != null ? 'Edit Question' : 'Add Question',
            ),
            actions: [
              TextButton(
                onPressed: _isValid ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
          body: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Question Type ──
                _buildQuestionTypeDropdown(),
                const SizedBox(height: 16),

                // ── Question Text ──
                _buildQuestionTextField(),
                if (_showValidation && _questionController.text.trim().isEmpty)
                  _buildErrorText('Question text is required'),
                const SizedBox(height: 16),

                // ── Options ──
                if (_isMcqType) ...[
                  _buildOptionsSection(),
                  const SizedBox(height: 16),
                ],

                // ── Difficulty ──
                _buildDifficultyDropdown(),
                const SizedBox(height: 16),

                // ── Marks ──
                _buildMarksFields(),
                if (_showValidation) ...[
                  if (int.tryParse(_marksController.text) == null ||
                      int.parse(_marksController.text) <= 0)
                    _buildErrorText('Valid marks are required'),
                ],
                const SizedBox(height: 16),

                // ── Explanation ──
                _buildExplanationField(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuestionTypeDropdown() {
    return DropdownButtonFormField<QuestionType>(
      initialValue: _questionType,
      decoration: const InputDecoration(labelText: 'Question Type *'),
      // V1: only MCQ (single) can be stored, answered and scored by the live
      // pipeline (index-based). The others are shown disabled as "Coming
      // soon" — never selectable, never given invented options.
      items: const [
        DropdownMenuItem(
          value: QuestionType.mcqSingle,
          child: Text('MCQ (Single Answer)'),
        ),
        DropdownMenuItem(
          value: QuestionType.mcqMultiple,
          enabled: false,
          child: Text('MCQ (Multiple Answers) — Coming soon'),
        ),
        DropdownMenuItem(
          value: QuestionType.trueFalse,
          enabled: false,
          child: Text('True / False — Coming soon'),
        ),
        DropdownMenuItem(
          value: QuestionType.integer,
          enabled: false,
          child: Text('Numeric — Coming soon'),
        ),
        DropdownMenuItem(
          value: QuestionType.shortAnswer,
          enabled: false,
          child: Text('Short Answer — Coming soon'),
        ),
      ],
      onChanged: (value) {
        if (value == null || !QuestionDraft.isSupportedType(value)) return;
        setState(() {
          _questionType = value;
          while (_options.length < QuestionDraft.minOptions) {
            _options = [..._options, const QuestionOptionDraft(text: '')];
          }
        });
      },
    );
  }

  Widget _buildQuestionTextField() {
    return TextFormField(
      controller: _questionController,
      decoration: InputDecoration(
        labelText: 'Question Text *',
        hintText: 'Enter your question',
        errorText: _showValidation && _questionController.text.trim().isEmpty
            ? 'Question text is required'
            : null,
        prefixIcon: const Icon(Icons.help_outline, size: 20),
      ),
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildOptionsSection() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Options',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_showValidation && !_isValid && _isMcqType)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'At least ${QuestionDraft.minOptions} options required, all filled in, with one correct answer',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ...List.generate(_options.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Radio<int>(
                  value: index,
                  groupValue: _correctOptionIndex,
                  onChanged: (value) {
                    setState(() => _correctOptionIndex = value);
                  },
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: _options[index].text,
                    decoration: InputDecoration(
                      hintText: 'Option ${index + 1}',
                      isDense: true,
                    ),
                    onChanged: (value) => _updateOption(index, value),
                  ),
                ),
                if (_options.length > QuestionDraft.minOptions)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () => _removeOption(index),
                    tooltip: 'Remove option',
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDifficultyDropdown() {
    return DropdownButtonFormField<DifficultyLevel>(
      initialValue: _difficulty,
      decoration: const InputDecoration(labelText: 'Difficulty'),
      items: const [
        DropdownMenuItem(value: DifficultyLevel.easy, child: Text('Easy')),
        DropdownMenuItem(value: DifficultyLevel.medium, child: Text('Medium')),
        DropdownMenuItem(value: DifficultyLevel.hard, child: Text('Hard')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _difficulty = value);
      },
    );
  }

  Widget _buildMarksFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _marksController,
            decoration: const InputDecoration(
              labelText: 'Marks *',
              hintText: '1',
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            controller: _negativeMarksController,
            decoration: const InputDecoration(
              labelText: 'Negative Marks',
              hintText: '0',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
      ],
    );
  }

  Widget _buildExplanationField() {
    return TextFormField(
      controller: _explanationController,
      decoration: const InputDecoration(
        labelText: 'Explanation (Optional)',
        hintText: 'Explain the correct answer',
        prefixIcon: Icon(Icons.lightbulb_outline, size: 20),
      ),
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildErrorText(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}
