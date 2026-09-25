import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../data/ai_generation_repository.dart';
import '../models/question_draft.dart';

/// Pre-selected data passed from the test creation wizard.
class AiGenerationPrefill {
  const AiGenerationPrefill({
    this.subject = '',
    this.topic = '',
    this.chapter = '',
    this.groupId,
    this.testMode = 'self',
    this.marksPerQuestion = 1,
    this.sourceText,
    this.sourceLabel,
  });

  final String subject;
  final String topic;
  final String chapter;
  final String? groupId;
  final String testMode;
  final double marksPerQuestion;

  /// Extracted text from a camera/file source (Phase 17/18/21): when
  /// present, generation is grounded in this content instead of the topic
  /// alone. Never sent when null/empty — a plain topic-only generation is
  /// unaffected.
  final String? sourceText;

  /// What to show the user for [sourceText] (e.g. the file name or
  /// "N photos"), purely for display.
  final String? sourceLabel;
}

/// Result returned when the user finishes AI generation and review.
class AiGenerationComplete {
  const AiGenerationComplete({
    required this.questions,
    required this.difficultyDistribution,
  });

  final List<QuestionDraft> questions;
  final Map<String, int> difficultyDistribution;
}

/// Full-screen AI question generation wizard.
///
/// Steps:
///  1. Configure (subject, topic, language, count, difficulty)
///  2. Generate (calls server-side AI)
///  3. Review & approve/reject questions
///  4. Return approved questions to the caller
class AiGenerationScreen extends StatefulWidget {
  const AiGenerationScreen({this.prefill, super.key});

  final AiGenerationPrefill? prefill;

  @override
  State<AiGenerationScreen> createState() => _AiGenerationScreenState();
}

class _AiGenerationScreenState extends State<AiGenerationScreen> {
  final _repo = const AiGenerationRepository();
  final _scrollController = ScrollController();

  int _step = 0; // 0=config, 1=generating, 2=review
  String? _error;
  bool _busy = false;

  // Configuration
  late String _subject;
  late String _topic;
  late String _chapter;
  late int _questionCount;
  late String _difficulty; // easy, medium, hard, mixed
  late Map<String, int> _difficultyDistribution;
  late String _language; // en, hi, hinglish
  late double _marksPerQuestion;

  // Generation result
  AiGenerationResult? _result;
  List<AiGeneratedQuestion> _questions = [];
  final Set<int> _rejectedIndices = {};
  final Set<int> _approvedIndices = {};

  // Available subjects (common Indian exam subjects)
  static const _subjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
    'Biology',
    'History',
    'Geography',
    'Political Science',
    'Economics',
    'English',
    'Hindi',
    'General Knowledge',
    'Computer Science',
    'Custom / Other',
  ];

  static const _languages = {
    'en': 'English',
    'hi': 'Hindi',
    'hinglish': 'Hinglish',
  };

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _subject = p?.subject ?? '';
    _topic = p?.topic ?? '';
    _chapter = p?.chapter ?? '';
    _questionCount = 10;
    _difficulty = 'mixed';
    _difficultyDistribution = {'easy': 3, 'medium': 4, 'hard': 3};
    _language = 'en';
    _marksPerQuestion = p?.marksPerQuestion ?? 1;

    // If subject is pre-filled and not in the list, we'll handle it as custom
    if (_subject.isNotEmpty && !_subjects.contains(_subject)) {
      _subject = 'Custom / Other';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Validation ──

  String? _validateConfig() {
    final subj = _subject == 'Custom / Other' ? _subject : _subject;
    if (subj.isEmpty) return 'Subject is required.';
    if (_topic.isEmpty && _chapter.isEmpty) {
      return 'Topic or Chapter is required.';
    }
    if (_questionCount < 1 || _questionCount > 30) {
      return 'Question count must be 1-30.';
    }
    if (_difficulty == 'mixed') {
      final sum = _difficultyDistribution.values.fold(0, (a, b) => a + b);
      if (sum != _questionCount) {
        return 'Difficulty distribution must sum to $_questionCount (currently $sum).';
      }
    }
    return null;
  }

  // ── Generation ──

  Future<void> _generate() async {
    final validationError = _validateConfig();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _step = 1;
      _error = null;
      _busy = true;
    });

    try {
      final effectiveSubject = _subject == 'Custom / Other' ? _topic : _subject;
      final effectiveTopic = _topic.isNotEmpty ? _topic : _chapter;

      final result = await _repo.generateQuestions(
        subject: effectiveSubject,
        topic: effectiveTopic,
        chapter: _chapter,
        questionCount: _questionCount,
        difficulty: _difficulty,
        difficultyDistribution: _difficulty == 'mixed'
            ? _difficultyDistribution
            : null,
        language: _language,
        questionType: 'mcq',
        marksPerQuestion: _marksPerQuestion,
        groupId: widget.prefill?.groupId,
        testMode: widget.prefill?.testMode ?? 'self',
        title: '$effectiveSubject - $effectiveTopic',
        sourceText: widget.prefill?.sourceText,
      );

      if (!mounted) return;

      setState(() {
        _result = result;
        _questions = result.questions;
        _rejectedIndices.clear();
        _approvedIndices.clear();
        // Auto-approve VALID questions
        for (var i = 0; i < _questions.length; i++) {
          if (_questions[i].isValid) {
            _approvedIndices.add(i);
          }
        }
        _step = 2;
        _busy = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _step = 0;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unexpected error: $e';
        _step = 0;
        _busy = false;
      });
    }
  }

  // ── Question actions ──

  void _toggleApproval(int index) {
    setState(() {
      if (_approvedIndices.contains(index)) {
        _approvedIndices.remove(index);
      } else {
        _rejectedIndices.remove(index);
        _approvedIndices.add(index);
      }
    });
  }

  void _toggleRejection(int index) {
    setState(() {
      if (_rejectedIndices.contains(index)) {
        _rejectedIndices.remove(index);
      } else {
        _approvedIndices.remove(index);
        _rejectedIndices.add(index);
      }
    });
  }

  void _approveAll() {
    setState(() {
      _approvedIndices.clear();
      _rejectedIndices.clear();
      for (var i = 0; i < _questions.length; i++) {
        _approvedIndices.add(i);
      }
    });
  }

  void _deleteQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
      // Rebuild index sets
      final newApproved = <int>{};
      final newRejected = <int>{};
      for (final i in _approvedIndices) {
        if (i < index) {
          newApproved.add(i);
        } else if (i > index)
          newApproved.add(i - 1);
      }
      for (final i in _rejectedIndices) {
        if (i < index) {
          newRejected.add(i);
        } else if (i > index)
          newRejected.add(i - 1);
      }
      _approvedIndices
        ..clear()
        ..addAll(newApproved);
      _rejectedIndices
        ..clear()
        ..addAll(newRejected);
    });
  }

  void _moveQuestion(int from, int to) {
    if (to < 0 || to >= _questions.length) return;
    setState(() {
      final q = _questions.removeAt(from);
      _questions.insert(to, q);
      // Rebuild index sets
      final newApproved = <int>{};
      final newRejected = <int>{};
      for (final i in _approvedIndices) {
        if (i == from) {
          newApproved.add(to);
        } else if (from < to && i > from && i <= to) {
          newApproved.add(i - 1);
        } else if (from > to && i >= to && i < from) {
          newApproved.add(i + 1);
        } else {
          newApproved.add(i);
        }
      }
      for (final i in _rejectedIndices) {
        if (i == from) {
          newRejected.add(to);
        } else if (from < to && i > from && i <= to) {
          newRejected.add(i - 1);
        } else if (from > to && i >= to && i < from) {
          newRejected.add(i + 1);
        } else {
          newRejected.add(i);
        }
      }
      _approvedIndices
        ..clear()
        ..addAll(newApproved);
      _rejectedIndices
        ..clear()
        ..addAll(newRejected);
    });
  }

  // ── Complete ──

  void _complete() {
    final approved = <QuestionDraft>[];
    final diffCounts = {'easy': 0, 'medium': 0, 'hard': 0};

    for (final i in _approvedIndices) {
      if (i < _questions.length) {
        final q = _questions[i];
        approved.add(q.toQuestionDraft(marks: _marksPerQuestion.toInt()));
        diffCounts[q.difficulty] = (diffCounts[q.difficulty] ?? 0) + 1;
      }
    }

    if (approved.isEmpty) {
      setState(() => _error = 'Approve at least one question.');
      return;
    }

    Navigator.of(context).pop(
      AiGenerationComplete(
        questions: approved,
        difficultyDistribution: diffCounts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _step == 0
              ? 'AI Generation'
              : _step == 1
              ? 'Generating...'
              : 'Review Questions',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _stepIndicator(),
          Expanded(child: _buildStep()),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _stepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= _step
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildConfigStep();
      case 1:
        return _buildGeneratingStep();
      case 2:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0: Configuration ──

  Widget _buildConfigStep() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Question Generator',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure the generation settings. AI will generate MCQ questions based on your configuration.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (widget.prefill?.sourceText?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('ai_source_banner'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Grounded in: ${widget.prefill?.sourceLabel ?? "your content"} — '
                      'AI will generate questions from this, not just the topic.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Subject
          _buildLabel('Subject *'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _subjects.contains(_subject) ? _subject : null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            items: _subjects
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v ?? ''),
          ),
          if (_subject == 'Custom / Other') ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Custom Subject',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _subject = v),
            ),
          ],
          const SizedBox(height: 16),

          // Topic & Chapter
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Topic *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      decoration: const InputDecoration(
                        hintText: 'e.g., Genetics',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _topic,
                      onChanged: (v) => setState(() => _topic = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Chapter'),
                    const SizedBox(height: 6),
                    TextFormField(
                      decoration: const InputDecoration(
                        hintText: 'e.g., Class 12 Biology',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _chapter,
                      onChanged: (v) => setState(() => _chapter = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Question Count
          _buildLabel('Number of Questions *'),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _questionCount = (_questionCount - 1).clamp(1, 30),
                ),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: TextFormField(
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _questionCount.toString(),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null) {
                      setState(() => _questionCount = n.clamp(1, 30));
                    }
                  },
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => _questionCount = (_questionCount + 1).clamp(1, 30),
                ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [5, 10, 15, 20, 30].map((n) {
              return ChoiceChip(
                label: Text('$n'),
                selected: _questionCount == n,
                onSelected: (_) => setState(() => _questionCount = n),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Difficulty
          _buildLabel('Difficulty'),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'mixed', label: Text('Mixed')),
              ButtonSegment(value: 'easy', label: Text('Easy')),
              ButtonSegment(value: 'medium', label: Text('Medium')),
              ButtonSegment(value: 'hard', label: Text('Hard')),
            ],
            selected: {_difficulty},
            onSelectionChanged: (v) {
              final d = v.first;
              setState(() {
                _difficulty = d;
                if (d == 'mixed') {
                  final base = _questionCount ~/ 3;
                  final rem = _questionCount % 3;
                  _difficultyDistribution = {
                    'easy': base + (rem >= 2 ? 1 : 0),
                    'medium': base + (rem >= 1 ? 1 : 0),
                    'hard': base,
                  };
                }
              });
            },
          ),
          if (_difficulty == 'mixed') ...[
            const SizedBox(height: 12),
            _buildDifficultyDistribution(),
          ],
          const SizedBox(height: 16),

          // Language
          _buildLabel('Language *'),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'hi', label: Text('Hindi')),
              ButtonSegment(value: 'hinglish', label: Text('Hinglish')),
            ],
            selected: {_language},
            onSelectionChanged: (v) => setState(() => _language = v.first),
          ),
          const SizedBox(height: 16),

          // Marks
          _buildLabel('Marks per Question'),
          const SizedBox(height: 6),
          TextFormField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            initialValue: _marksPerQuestion.toString(),
            onChanged: (v) {
              final d = double.tryParse(v);
              if (d != null) setState(() => _marksPerQuestion = d);
            },
          ),
          const SizedBox(height: 20),

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generation Summary', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Subject',
                    _subject == 'Custom / Other' ? _topic : _subject,
                  ),
                  _summaryRow('Topic', _topic.isNotEmpty ? _topic : _chapter),
                  _summaryRow('Count', '$_questionCount questions'),
                  _summaryRow('Difficulty', _difficulty),
                  _summaryRow('Language', _languages[_language] ?? _language),
                  _summaryRow(
                    'Marks',
                    '${_marksPerQuestion.toInt()} per question',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyDistribution() {
    final sum = _difficultyDistribution.values.fold(0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Distribution',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$sum / $_questionCount',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: sum == _questionCount
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final tier in ['easy', 'medium', 'hard'])
              Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      tier[0].toUpperCase() + tier.substring(1),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _difficultyDistribution[tier] =
                          (_difficultyDistribution[tier]! - 1).clamp(0, 99);
                    }),
                    icon: const Icon(Icons.remove, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${_difficultyDistribution[tier]}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final currentSum = _difficultyDistribution.values.fold(
                        0,
                        (a, b) => a + b,
                      );
                      if (currentSum < _questionCount) {
                        setState(
                          () => _difficultyDistribution[tier] =
                              _difficultyDistribution[tier]! + 1,
                        );
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            if (sum != _questionCount)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Must sum to $_questionCount',
                  style: const TextStyle(color: AppColors.error, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    );
  }

  // ── Step 1: Generating ──

  Widget _buildGeneratingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Generating $_questionCount questions...',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'AI is creating ${_language == "hi"
                  ? "Hindi"
                  : _language == "hinglish"
                  ? "Hinglish"
                  : "English"} MCQ questions for ${_subject == "Custom / Other" ? _topic : _subject}.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Review ──

  Widget _buildReviewStep() {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              _reviewStat('Total', _questions.length, Colors.blue),
              const SizedBox(width: 12),
              _reviewStat(
                'Approved',
                _approvedIndices.length,
                AppColors.success,
              ),
              const SizedBox(width: 12),
              _reviewStat('Rejected', _rejectedIndices.length, AppColors.error),
              const Spacer(),
              if (_result != null)
                Text(
                  _result!.cacheHit
                      ? 'Cache hit'
                      : '${_result!.tokensIn}/${_result!.tokensOut} tokens',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
            ],
          ),
        ),

        // Question list
        Expanded(
          child: _questions.isEmpty
              ? const Center(child: Text('No questions generated.'))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  itemBuilder: (context, index) => _buildQuestionCard(index),
                ),
        ),
      ],
    );
  }

  Widget _reviewStat(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildQuestionCard(int index) {
    final q = _questions[index];
    final isApproved = _approvedIndices.contains(index);
    final isRejected = _rejectedIndices.contains(index);
    final theme = Theme.of(context);

    Color borderColor;
    if (isApproved) {
      borderColor = AppColors.success;
    } else if (isRejected) {
      borderColor = AppColors.error;
    } else if (q.needsReview) {
      borderColor = AppColors.warning;
    } else {
      borderColor = theme.colorScheme.outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(q.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    q.status.replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor(q.status),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(q.confidence * 100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                Text(
                  ' • ${q.difficulty}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Question text
            Text(
              q.question,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),

            // Options
            for (var i = 0; i < q.options.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: q.correctOption == i
                      ? AppColors.success.withValues(alpha: 0.1)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: q.correctOption == i
                      ? Border.all(
                          color: AppColors.success.withValues(alpha: 0.3),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Text(
                      '${String.fromCharCode(65 + i)}. ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: q.correctOption == i ? AppColors.success : null,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        q.options[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: q.correctOption == i
                              ? AppColors.success
                              : null,
                        ),
                      ),
                    ),
                    if (q.correctOption == i)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 16,
                      ),
                  ],
                ),
              ),

            // Explanation
            if (q.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        q.explanation,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Reason
            if (q.reason != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      q.reason!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleApproval(index),
                    icon: Icon(
                      isApproved
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      size: 16,
                      color: isApproved ? AppColors.success : null,
                    ),
                    label: Text(
                      isApproved ? 'Approved' : 'Approve',
                      style: TextStyle(
                        color: isApproved ? AppColors.success : null,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: isApproved
                          ? const BorderSide(color: AppColors.success)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleRejection(index),
                    icon: Icon(
                      isRejected ? Icons.cancel : Icons.cancel_outlined,
                      size: 16,
                      color: isRejected ? AppColors.error : null,
                    ),
                    label: Text(
                      isRejected ? 'Rejected' : 'Reject',
                      style: TextStyle(
                        color: isRejected ? AppColors.error : null,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: isRejected
                          ? const BorderSide(color: AppColors.error)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: index > 0
                      ? () => _moveQuestion(index, index - 1)
                      : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Move up',
                ),
                IconButton(
                  onPressed: index < _questions.length - 1
                      ? () => _moveQuestion(index, index + 1)
                      : null,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: 'Move down',
                ),
                IconButton(
                  onPressed: () => _deleteQuestion(index),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.error,
                  ),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'VALID':
        return AppColors.success;
      case 'NEEDS_REVIEW':
        return AppColors.warning;
      case 'INVALID':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }

  // ── Bottom bar ──

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_step > 0 && _step != 1)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _step = _step == 2 ? 0 : _step - 1),
                child: const Text('Back'),
              ),
            const Spacer(),
            if (_step == 0)
              FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate'),
              )
            else if (_step == 2) ...[
              OutlinedButton(
                onPressed: _approveAll,
                child: const Text('Approve All'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _approvedIndices.isEmpty ? null : _complete,
                child: Text('Use ${_approvedIndices.length} Questions'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
