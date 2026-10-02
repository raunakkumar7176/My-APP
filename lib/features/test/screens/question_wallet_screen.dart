import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/question.dart';
import '../../../core/theme/app_colors.dart';
import '../data/question_repository.dart';
import '../data/question_wallet_repository.dart';
import '../domain/question_wallet_models.dart';

/// "Question Wallet" — reuse questions from the caller's own past tests
/// (clone a whole test, hand-pick specific questions, or pull every
/// question they've ever gotten wrong into one revision test) instead of
/// writing or AI-generating everything from scratch every time.
class QuestionWalletScreen extends StatefulWidget {
  const QuestionWalletScreen({super.key});

  @override
  State<QuestionWalletScreen> createState() => _QuestionWalletScreenState();
}

class _QuestionWalletScreenState extends State<QuestionWalletScreen> {
  final _repo = const SupabaseQuestionWalletRepository();
  List<PastTestSummary> _pastTests = [];
  List<MistakeTestGroup> _mistakeGroups = [];
  bool _isLoading = true;
  bool _mistakesLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _mistakesLoading = true;
      _error = null;
    });
    try {
      final tests = await _repo.myPastTests();
      if (!mounted) return;
      setState(() {
        _pastTests = tests;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your past tests.';
        _isLoading = false;
      });
    }
    try {
      final groups = await _repo.mistakeTestsSummary();
      if (!mounted) return;
      setState(() {
        _mistakeGroups = groups;
        _mistakesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mistakesLoading = false);
    }
  }

  Future<void> _retestMistakeGroup(MistakeTestGroup group) async {
    await _confirmAndCreateSelfTest(
      defaultTitle: '${group.testTitle} (Mistakes)',
      questionIds: group.mistakeQuestionIds,
    );
  }

  Future<void> _confirmAndCreateSelfTest({
    required String defaultTitle,
    required List<String> questionIds,
  }) async {
    final titleController = TextEditingController(text: defaultTitle);
    final minutesController = TextEditingController(
      text: '${(questionIds.length * 1.2).ceil().clamp(5, 180)}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-test Your Mistakes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Test Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (minutes)'),
            ),
            const SizedBox(height: 8),
            Text(
              '${questionIds.length} mistake${questionIds.length == 1 ? '' : 's'} selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Start')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final minutes = int.tryParse(minutesController.text.trim()) ?? 30;
    try {
      final newTestId = await _repo.createSelfTestFromMistakes(
        title: titleController.text.trim().isEmpty ? defaultTitle : titleController.text.trim(),
        durationSec: (minutes.clamp(1, 360)) * 60,
        questionIds: questionIds,
      );
      if (!mounted) return;
      context.push('/tests/$newTestId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the test: $e')),
      );
    }
  }

  Future<void> _openTestOptions(PastTestSummary test) async {
    final choice = await showModalBottomSheet<_ReuseChoice>(
      context: context,
      builder: (ctx) => _ReuseChoiceSheet(test: test),
    );
    if (choice == null || !mounted) return;

    if (choice == _ReuseChoice.cloneAll) {
      final questions = await _repo.questionsForReuse(test.testId);
      if (!mounted) return;
      await _openPicker(
        title: test.title,
        subtitle: 'All ${questions.length} questions selected.',
        questions: questions,
        allSelectedByDefault: true,
        defaultTitle: '${test.title} (Retest)',
      );
    } else {
      final questions = await _repo.questionsForReuse(test.testId);
      if (!mounted) return;
      await _openPicker(
        title: test.title,
        subtitle: 'Pick the questions you want to reuse.',
        questions: questions,
        allSelectedByDefault: false,
        defaultTitle: '${test.title} (Selected)',
      );
    }
  }

  Future<void> _openPicker({
    required String title,
    required String subtitle,
    required List<ReusableQuestion> questions,
    required bool allSelectedByDefault,
    required String defaultTitle,
  }) async {
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No questions found.')),
      );
      return;
    }
    final selectedIds = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _QuestionPickerScreen(
          title: title,
          subtitle: subtitle,
          questions: questions,
          allSelectedByDefault: allSelectedByDefault,
        ),
      ),
    );
    if (selectedIds == null || selectedIds.isEmpty || !mounted) return;
    await _confirmAndCreate(defaultTitle: defaultTitle, questionIds: selectedIds);
  }

  Future<void> _confirmAndCreate({
    required String defaultTitle,
    required List<String> questionIds,
  }) async {
    final titleController = TextEditingController(text: defaultTitle);
    final minutesController = TextEditingController(
      text: '${(questionIds.length * 1.2).ceil().clamp(5, 180)}',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Test'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Test Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (minutes)'),
            ),
            const SizedBox(height: 8),
            Text(
              '${questionIds.length} question${questionIds.length == 1 ? '' : 's'} selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final minutes = int.tryParse(minutesController.text.trim()) ?? 30;
    try {
      final newTestId = await _repo.createTestFromReusedQuestions(
        title: titleController.text.trim().isEmpty ? defaultTitle : titleController.text.trim(),
        durationSec: (minutes.clamp(1, 360)) * 60,
        questionIds: questionIds,
      );
      if (!mounted) return;
      context.push('/tests/$newTestId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the test: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Question Wallet')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Text(
              'Mistake Vault',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            'Mistakes stay here for 30 days — star ⭐ one to keep it forever.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (_mistakesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_mistakeGroups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('No mistakes found yet — great job!')),
          )
        else
          for (final group in _mistakeGroups)
            _MistakeGroupCard(
              group: group,
              onRetest: () => _retestMistakeGroup(group),
              onStarChanged: _load,
            ),
        const SizedBox(height: 16),
        Text(
          'Your Past Tests',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_pastTests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No past tests with questions yet.')),
          )
        else
          for (final test in _pastTests)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(test.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${test.totalQuestions} questions · ${test.status}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openTestOptions(test),
              ),
            ),
      ],
    );
  }
}

class _MistakeGroupCard extends StatefulWidget {
  const _MistakeGroupCard({
    required this.group,
    required this.onRetest,
    required this.onStarChanged,
  });

  final MistakeTestGroup group;
  final VoidCallback onRetest;
  final VoidCallback onStarChanged;

  @override
  State<_MistakeGroupCard> createState() => _MistakeGroupCardState();
}

class _MistakeGroupCardState extends State<_MistakeGroupCard> {
  final _questionRepo = const SupabaseQuestionRepository();
  final _walletRepo = const SupabaseQuestionWalletRepository();
  bool _expanded = false;
  bool _loadingQuestions = false;
  List<Question>? _questions;

  String _relativeDate(DateTime? dt) {
    if (dt == null) return '';
    final days = DateTime.now().difference(dt).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }

  Future<void> _toggleExpanded() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _questions == null) {
      setState(() => _loadingQuestions = true);
      try {
        final all = await _questionRepo.reviewQuestionsForAttempt(widget.group.attemptId);
        final ids = widget.group.mistakeQuestionIds.toSet();
        if (!mounted) return;
        setState(() {
          _questions = all.where((q) => ids.contains(q.id)).toList();
          _loadingQuestions = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loadingQuestions = false);
      }
    }
  }

  Future<void> _toggleStar(String questionId, bool starred) async {
    try {
      await _walletRepo.toggleMistakeStar(
        attemptId: widget.group.attemptId,
        questionId: questionId,
        starred: starred,
      );
      widget.onStarChanged();
    } catch (_) {
      // Best-effort: star is a convenience, not worth a blocking error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(g.testTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_relativeDate(g.attemptedAt)} · ${g.totalMistakes} mistake${g.totalMistakes == 1 ? '' : 's'}'),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: _toggleExpanded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: OutlinedButton.icon(
              onPressed: widget.onRetest,
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: Text('Re-test only ${g.totalMistakes} mistake${g.totalMistakes == 1 ? '' : 's'}'),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _loadingQuestions
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      children: [
                        for (final q in _questions ?? const <Question>[])
                          ListTile(
                            dense: true,
                            title: Text(q.question, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.star_border_rounded),
                              tooltip: 'Keep this mistake forever',
                              onPressed: () => _toggleStar(q.id, true),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

enum _ReuseChoice { cloneAll, pickSpecific }

class _ReuseChoiceSheet extends StatelessWidget {
  const _ReuseChoiceSheet({required this.test});

  final PastTestSummary test;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(test.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.content_copy_outlined, color: AppColors.primaryLight),
              title: const Text('Clone Entire Test'),
              subtitle: Text('All ${test.totalQuestions} questions, new test/timer.'),
              onTap: () => Navigator.of(context).pop(_ReuseChoice.cloneAll),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_outlined, color: AppColors.secondaryLight),
              title: const Text('Pick Specific Questions'),
              subtitle: const Text('Choose which ones to reuse.'),
              onTap: () => Navigator.of(context).pop(_ReuseChoice.pickSpecific),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionPickerScreen extends StatefulWidget {
  const _QuestionPickerScreen({
    required this.title,
    required this.subtitle,
    required this.questions,
    required this.allSelectedByDefault,
  });

  final String title;
  final String subtitle;
  final List<ReusableQuestion> questions;
  final bool allSelectedByDefault;

  @override
  State<_QuestionPickerScreen> createState() => _QuestionPickerScreenState();
}

class _QuestionPickerScreenState extends State<_QuestionPickerScreen> {
  late final Set<String> _selected = widget.allSelectedByDefault
      ? {for (final q in widget.questions) q.questionId}
      : {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(child: Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall)),
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == widget.questions.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(widget.questions.map((q) => q.questionId));
                    }
                  }),
                  child: Text(_selected.length == widget.questions.length ? 'Clear All' : 'Select All'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: widget.questions.length,
              itemBuilder: (context, i) {
                final q = widget.questions[i];
                final checked = _selected.contains(q.questionId);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(q.questionId);
                    } else {
                      _selected.remove(q.questionId);
                    }
                  }),
                  title: Text(q.question, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: q.sourceTestTitle != null
                      ? Text('From: ${q.sourceTestTitle}', style: const TextStyle(fontSize: 11.5))
                      : null,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                child: Text('Create Test with ${_selected.length} Question${_selected.length == 1 ? '' : 's'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
