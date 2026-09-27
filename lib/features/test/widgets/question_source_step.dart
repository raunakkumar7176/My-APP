import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/question_bank_item.dart';
import '../../../core/models/subject.dart';
import '../../../core/models/syllabus_node.dart';
import '../../../core/services/subject_service.dart';
import '../../../core/services/syllabus_service.dart';
import '../data/question_bank_repository.dart';
import '../domain/json_question_parser.dart';
import '../models/question_draft.dart';
import '../screens/ai_generation_screen.dart';
import 'section_card.dart';

/// Where the test's questions come from.
/// - [manual]: Write questions yourself, or paste a raw JSON array
/// - [myStudy]: Cascading Subject → Chapter scoped to the question bank
/// - [document]: Extract from PDF/Word/Excel (V1 — implemented)
/// - [ai]: AI-generated questions (V1 — implemented)
/// - [books]: Select from the question bank (R7 - implemented)
///
/// [document] and [ai] are shown as ONE tile ("Smart Document & AI") in the
/// picker below — both already funnel through the same `_AiSourceChooser`
/// bottom sheet (Camera/File → document import, Enter Topic → AI
/// generation), so this only changes the visible grouping, not the pipelines.
enum QuestionSource { manual, myStudy, document, ai, books }

extension QuestionSourceInfo on QuestionSource {
  String get label {
    switch (this) {
      case QuestionSource.manual:
        return 'Manual / JSON Paste';
      case QuestionSource.myStudy:
        return 'My Study';
      case QuestionSource.document:
      case QuestionSource.ai:
        return 'Smart Document & AI';
      case QuestionSource.books:
        return 'Question Bank';
    }
  }

  String get description {
    switch (this) {
      case QuestionSource.manual:
        return 'Write questions yourself, or paste a JSON array to generate them instantly.';
      case QuestionSource.myStudy:
        return 'Pick a subject and chapter you\'re studying; pulls from the question bank scoped to it.';
      case QuestionSource.document:
      case QuestionSource.ai:
        return 'Upload PDF / Word / TXT / Image or enter a topic → generated or extracted questions → review before publish.';
      case QuestionSource.books:
        return 'Filter by difficulty and PYQ status, then browse the question bank.';
    }
  }

  /// True only when a real backend pipeline exists in this build.
  bool get isAvailable => true;

  IconData get icon {
    switch (this) {
      case QuestionSource.manual:
        return Icons.edit_note;
      case QuestionSource.myStudy:
        return Icons.school_outlined;
      case QuestionSource.document:
      case QuestionSource.ai:
        return Icons.auto_awesome_outlined;
      case QuestionSource.books:
        return Icons.menu_book_outlined;
    }
  }

  /// `tests.creation_method` value (`manual|upload|ai`) — sent only for
  /// sources that actually run; the wizard always persists `manual` today.
  String get creationMethod {
    switch (this) {
      case QuestionSource.manual:
        return 'manual';
      case QuestionSource.myStudy:
        return 'manual';
      case QuestionSource.document:
        return 'upload';
      case QuestionSource.ai:
        return 'ai';
      case QuestionSource.books:
        return 'manual';
    }
  }
}

/// The 4 tiles actually shown in the picker (document+ai collapse to one).
const _pickerSources = [
  QuestionSource.myStudy,
  QuestionSource.books,
  QuestionSource.document,
  QuestionSource.manual,
];

/// Question Source step. Every source here runs a real pipeline — there is
/// no "Not configured" placeholder any more (all 4 consolidated sources are
/// implemented).
class QuestionSourceStep extends StatefulWidget {
  const QuestionSourceStep({
    required this.selected,
    required this.onChanged,
    this.onBankQuestionsSelected,
    this.onDocumentQuestionsSelected,
    this.onAiQuestionsSelected,
    this.onJsonQuestionsSelected,
    this.groupId,
    this.testMode = 'self',
    this.subject = '',
    this.subjectId,
    this.topic = '',
    this.chapter = '',
    this.marksPerQuestion = 1,
    super.key,
  });

  final QuestionSource selected;
  final ValueChanged<QuestionSource> onChanged;

  /// Called when user selects questions from the bank.
  final ValueChanged<List<QuestionBankItem>>? onBankQuestionsSelected;

  /// Called when user confirms questions from a document import.
  final ValueChanged<List<QuestionDraft>>? onDocumentQuestionsSelected;

  /// Called when user completes AI generation and review.
  final ValueChanged<List<QuestionDraft>>? onAiQuestionsSelected;

  /// Called when a pasted JSON payload parses into valid drafts.
  final ValueChanged<List<QuestionDraft>>? onJsonQuestionsSelected;

  /// Group context for document upload (for group-scoped storage).
  final String? groupId;

  /// Test mode for AI generation context.
  final String testMode;

  /// Pre-filled subject NAME for AI generation (display text).
  final String subject;

  /// Pre-filled subject ID (e.g. from "Take a Chapter Test") — used by
  /// My Study to auto-select the same subject the syllabus step prefilled.
  final String? subjectId;

  /// Pre-filled topic for AI generation.
  final String topic;

  /// Pre-filled chapter for AI generation.
  final String chapter;

  /// Marks per question for AI generation.
  final double marksPerQuestion;

  @override
  State<QuestionSourceStep> createState() => _QuestionSourceStepState();
}

class _QuestionSourceStepState extends State<QuestionSourceStep> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _displaySource(widget.selected);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question Source',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how questions get into this test.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // ── Source Selection ──
          SectionCard(
            title: 'Select Source',
            children: [
              for (final s in _pickerSources)
                _SourceTile(
                  source: s,
                  isSelected: s == selected,
                  onSelect: () => _onSelect(context, s),
                ),
            ],
          ),

          const SizedBox(height: 16),
          if (widget.selected == QuestionSource.myStudy)
            _MyStudySource(
              initialSubjectId: widget.subjectId,
              onOpenQuestionBank: (subjectName, chapter) =>
                  _openQuestionBank(context, subjectName: subjectName, chapter: chapter),
            )
          else if (widget.selected == QuestionSource.books)
            _QuestionBankSource(
              onBrowse: (difficulty, pyqOnly) => _openQuestionBank(
                context,
                difficulty: difficulty,
                pyqOnly: pyqOnly,
              ),
            )
          else if (widget.selected == QuestionSource.manual)
            _ManualOrJsonSource(
              onJsonParsed: (drafts) => widget.onJsonQuestionsSelected?.call(drafts),
            ),
        ],
      ),
    );
  }

  /// document/ai share one tile; the tile shows selected whenever either
  /// underlying enum value is the current selection.
  QuestionSource _displaySource(QuestionSource s) =>
      s == QuestionSource.ai ? QuestionSource.document : s;

  void _onSelect(BuildContext context, QuestionSource s) {
    widget.onChanged(s);
    if (s == QuestionSource.books) {
      // Selecting the tile alone just reveals the inline filters below;
      // browsing happens via _QuestionBankSource's own button.
    } else if (s == QuestionSource.document) {
      _openAiGeneration(context);
    }
  }

  Future<void> _openQuestionBank(
    BuildContext context, {
    String? subjectName,
    String? chapter,
    String? difficulty,
    bool pyqOnly = false,
  }) async {
    final result = await context.push<List<QuestionBankItem>>(
      '/question-bank',
      extra: {
        'selectionMode': true,
        'onSelectionConfirmed': widget.onBankQuestionsSelected,
        'initialFilter': QuestionBankFilter(
          subjectName: subjectName,
          chapter: chapter,
          difficulty: difficulty,
          pyqOnly: pyqOnly,
        ),
      },
    );

    if (result != null &&
        result.isNotEmpty &&
        widget.onBankQuestionsSelected != null) {
      widget.onBankQuestionsSelected!(result);
    }
  }

  Future<void> _openDocumentImport(BuildContext context) async {
    final drafts = await context.push<List<QuestionDraft>>(
      '/tests/create/document-import',
      extra: {'groupId': widget.groupId},
    );

    if (drafts != null &&
        drafts.isNotEmpty &&
        widget.onDocumentQuestionsSelected != null) {
      widget.onDocumentQuestionsSelected!(drafts);
    }
  }

  Future<void> _openAiGeneration(BuildContext context) async {
    final choice = await showModalBottomSheet<_AiSourceChoice>(
      context: context,
      builder: (ctx) => const _AiSourceChooser(),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case _AiSourceChoice.topic:
        await _pushAiGeneration(context, const AiGenerationPrefill());
      case _AiSourceChoice.camera:
      case _AiSourceChoice.file:
        await _openDocumentImport(context);
    }
  }

  Future<void> _pushAiGeneration(
    BuildContext context,
    AiGenerationPrefill base,
  ) async {
    final result = await context.push<AiGenerationComplete>(
      '/tests/create/ai-generate',
      extra: AiGenerationPrefill(
        subject: widget.subject.isNotEmpty ? widget.subject : base.subject,
        topic: widget.topic.isNotEmpty ? widget.topic : base.topic,
        chapter: widget.chapter.isNotEmpty ? widget.chapter : base.chapter,
        groupId: widget.groupId,
        testMode: widget.testMode,
        marksPerQuestion: widget.marksPerQuestion,
        sourceText: base.sourceText,
        sourceLabel: base.sourceLabel,
      ),
    );

    if (result != null &&
        result.questions.isNotEmpty &&
        widget.onAiQuestionsSelected != null) {
      widget.onAiQuestionsSelected!(result.questions);
    }
  }
}

enum _AiSourceChoice { camera, file, topic }

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.isSelected,
    required this.onSelect,
  });

  final QuestionSource source;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          key: Key('source_tile_${source.name}'),
          onTap: onSelect,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    source.icon,
                    size: 22,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Source A: cascading Subject → Chapter, backed by the same `subjects` /
/// `syllabus_nodes` tables the Syllabus step uses (real ids, no mock data),
/// with a genuine available-question count from the question bank.
class _MyStudySource extends StatefulWidget {
  const _MyStudySource({required this.initialSubjectId, required this.onOpenQuestionBank});

  final String? initialSubjectId;
  final void Function(String subjectName, String chapter) onOpenQuestionBank;

  @override
  State<_MyStudySource> createState() => _MyStudySourceState();
}

class _MyStudySourceState extends State<_MyStudySource> {
  final _repo = const SupabaseQuestionBankRepository();
  List<Subject> _subjects = [];
  List<SyllabusNode> _nodes = [];
  Subject? _subject;
  SyllabusNode? _chapter;
  bool _loadingSubjects = true;
  bool _loadingNodes = false;
  int? _count;
  bool _loadingCount = false;

  @override
  void initState() {
    super.initState();
    SubjectService.loadSubjects().then((subjects) {
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _loadingSubjects = false;
      });
      if (widget.initialSubjectId != null) {
        final match = subjects.where((s) => s.id == widget.initialSubjectId);
        if (match.isNotEmpty) _selectSubject(match.first);
      }
    }).catchError((_) {
      if (mounted) setState(() => _loadingSubjects = false);
    });
  }

  void _selectSubject(Subject subject) {
    setState(() {
      _subject = subject;
      _chapter = null;
      _nodes = [];
      _loadingNodes = true;
      _count = null;
    });
    SyllabusService.loadNodesForSubject(subject.id).then((nodes) {
      if (!mounted) return;
      setState(() {
        _nodes = nodes;
        _loadingNodes = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loadingNodes = false);
    });
  }

  Future<void> _selectChapter(SyllabusNode node) async {
    setState(() {
      _chapter = node;
      _loadingCount = true;
      _count = null;
    });
    try {
      final count = await _repo.getAvailableCount(
        subjectName: _subject?.name,
        chapter: node.name,
      );
      if (mounted) setState(() => _count = count);
    } catch (_) {
      if (mounted) setState(() => _count = null);
    } finally {
      if (mounted) setState(() => _loadingCount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'My Study',
      subtitle: 'Pick your subject and chapter.',
      children: [
        if (_loadingSubjects)
          const Center(child: CircularProgressIndicator())
        else
          DropdownButtonFormField<Subject>(
            key: const Key('my_study_subject_dropdown'),
            initialValue: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: [
              for (final s in _subjects)
                DropdownMenuItem(value: s, child: Text(s.name)),
            ],
            onChanged: (v) {
              if (v != null) _selectSubject(v);
            },
          ),
        if (_subject != null) ...[
          const SizedBox(height: 12),
          if (_loadingNodes)
            const Center(child: CircularProgressIndicator())
          else if (_nodes.isEmpty)
            Text(
              'No chapters found for ${_subject!.name}.',
              style: theme.textTheme.bodySmall,
            )
          else
            DropdownButtonFormField<SyllabusNode>(
              key: const Key('my_study_chapter_dropdown'),
              initialValue: _chapter,
              decoration: const InputDecoration(labelText: 'Chapter'),
              items: [
                for (final n in _nodes)
                  DropdownMenuItem(value: n, child: Text(n.name)),
              ],
              onChanged: (v) {
                if (v != null) _selectChapter(v);
              },
            ),
        ],
        if (_chapter != null) ...[
          const SizedBox(height: 12),
          if (_loadingCount)
            const LinearProgressIndicator()
          else
            Text(
              _count == null
                  ? 'Could not load the question pool count.'
                  : '$_count question${_count == 1 ? '' : 's'} available for ${_chapter!.name}.',
              key: const Key('my_study_count_text'),
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('my_study_use_questions_btn'),
            onPressed: (_count ?? 0) > 0
                ? () => widget.onOpenQuestionBank(_subject!.name, _chapter!.name)
                : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Use These Questions'),
          ),
        ],
      ],
    );
  }
}

/// Source B: Question Bank — difficulty pills + PYQ toggle before browsing.
class _QuestionBankSource extends StatefulWidget {
  const _QuestionBankSource({required this.onBrowse});

  final void Function(String? difficulty, bool pyqOnly) onBrowse;

  @override
  State<_QuestionBankSource> createState() => _QuestionBankSourceState();
}

class _QuestionBankSourceState extends State<_QuestionBankSource> {
  String? _difficulty;
  bool _pyqOnly = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Question Bank',
      subtitle: 'Filter, then browse the bank.',
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final d in const ['easy', 'medium', 'hard'])
              ChoiceChip(
                key: Key('qb_difficulty_$d'),
                label: Text(d[0].toUpperCase() + d.substring(1)),
                selected: _difficulty == d,
                onSelected: (on) => setState(() => _difficulty = on ? d : null),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('qb_pyq_only_switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Only PYQs (Previous Year Questions)'),
          value: _pyqOnly,
          onChanged: (v) => setState(() => _pyqOnly = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('qb_browse_btn'),
          onPressed: () => widget.onBrowse(_difficulty, _pyqOnly),
          icon: const Icon(Icons.search),
          label: const Text('Browse Question Bank'),
        ),
      ],
    );
  }
}

/// Source D: write manually (existing Questions step) or paste raw JSON.
class _ManualOrJsonSource extends StatefulWidget {
  const _ManualOrJsonSource({required this.onJsonParsed});

  final ValueChanged<List<QuestionDraft>> onJsonParsed;

  @override
  State<_ManualOrJsonSource> createState() => _ManualOrJsonSourceState();
}

class _ManualOrJsonSourceState extends State<_ManualOrJsonSource> {
  final _controller = TextEditingController();
  List<String> _errors = const [];
  int _parsedCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final result = JsonQuestionParser.parse(_controller.text);
    setState(() {
      _errors = result.errors;
      _parsedCount = result.drafts.length;
    });
    if (result.isValid) {
      widget.onJsonParsed(result.drafts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Paste JSON / Raw MCQ',
      subtitle: 'Write questions in the Questions step, or paste a JSON array here.',
      children: [
        TextField(
          key: const Key('json_paste_field'),
          controller: _controller,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: const InputDecoration(
            hintText:
                '[{"question": "...", "options": ["A","B","C","D"], '
                '"correct_option": 0, "explanation": "..."}]',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('json_paste_parse_btn'),
          onPressed: _parse,
          icon: const Icon(Icons.data_object),
          label: const Text('Paste JSON / Raw MCQ'),
        ),
        if (_errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('json_paste_errors'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in _errors)
                  Text(e, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ],
            ),
          ),
        ] else if (_parsedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              key: const Key('json_paste_success'),
              '$_parsedCount question${_parsedCount == 1 ? '' : 's'} added.',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
      ],
    );
  }
}

class _AiSourceChooser extends StatelessWidget {
  const _AiSourceChooser();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How should AI get the topic?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const Key('ai_source_camera'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photos'),
              onTap: () => Navigator.of(context).pop(_AiSourceChoice.camera),
            ),
            ListTile(
              key: const Key('ai_source_file'),
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Choose File'),
              onTap: () => Navigator.of(context).pop(_AiSourceChoice.file),
            ),
            ListTile(
              key: const Key('ai_source_topic'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Enter Topic'),
              onTap: () => Navigator.of(context).pop(_AiSourceChoice.topic),
            ),
          ],
        ),
      ),
    );
  }
}
