import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../domain/attempt_policy.dart';
import '../domain/creation_settings.dart';
import '../domain/test_kind.dart';
import '../state/test_creation_controller.dart';
import '../widgets/basic_details_step.dart';
import '../widgets/configuration_step.dart';
import '../widgets/question_source_step.dart';
import '../widgets/questions_step.dart';
import '../widgets/review_step.dart';
import '../widgets/step_syllabus.dart';

/// Five-step wizard over [TestCreationController]. The screen holds only
/// the current step index; all data and persistence live in the controller.
class TestCreationScreen extends StatefulWidget {
  const TestCreationScreen({
    this.testId,
    this.controller,
    this.initialSource,
    this.initialGroupId,
    super.key,
  });

  /// G10: opened from a group's test management — the wizard starts as a
  /// Group Test scoped to this group (the user may still change it; the
  /// server enforces CREATE_TEST for the group on save).
  final String? initialGroupId;

  /// Pre-selected question source (Home tiles); unavailable sources open the
  /// wizard on the truthful "Not configured" step.
  final QuestionSource? initialSource;

  /// Present when editing an existing draft (/tests/:id/edit).
  final String? testId;
  final TestCreationController? controller;

  // Syllabus (scope) comes before Source/Questions so a difficulty target
  // is always defined within the selected concept.
  static const stepTitles = [
    'Basic Details',
    'Configuration',
    'Syllabus',
    'Question Source',
    'Questions',
    'Review',
  ];

  @override
  State<TestCreationScreen> createState() => _TestCreationScreenState();
}

class _TestCreationScreenState extends State<TestCreationScreen> {
  late final TestCreationController _c;
  late final bool _owns;
  // A Home tile for an unavailable source lands directly on the source step.
  late int _step =
      (widget.initialSource != null && !widget.initialSource!.isAvailable)
      ? 3
      : 0;
  late QuestionSource _source = widget.initialSource ?? QuestionSource.manual;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        TestCreationController(editingTestId: widget.testId);
    _c.addListener(_onChanged);
    _c.loadGroups();
    if (widget.testId != null) {
      _c.loadForEdit();
    } else if (widget.initialGroupId != null) {
      _c.presetGroup(widget.initialGroupId!);
    }
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

  bool get _canProceed {
    switch (_step) {
      case 0:
        return _c.canProceedFromBasics;
      case 1:
        return _c.canProceedFromConfiguration;
      case 2:
        return !_c.kind.requiresScope || _c.syllabusNodeIds.isNotEmpty;
      case 3:
        return _source.isAvailable;
      case 4:
        return _c.hasAnyQuestion;
      default:
        return true;
    }
  }

  void _snack(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _saveDraft() async {
    try {
      await _c.saveDraft();
      if (!mounted) return;
      final leave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: 48,
          ),
          title: const Text('Draft Saved'),
          content: const Text('Your test has been saved as a draft.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Back to Tests'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Continue Editing'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) context.pop();
    } on AppError catch (e) {
      if (mounted) _snack(e.message, error: true);
    }
  }

  Future<void> _publish() async {
    try {
      await _c.publish();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: 48,
          ),
          title: const Text('Test Published'),
          content: const Text('Your test is now published and available.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Back to Tests'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/tests');
    } on ValidationError catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 48,
          ),
          title: const Text('Not ready to publish'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on AppError catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 48,
          ),
          title: const Text('Publish Failed'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Test…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
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
                const SizedBox(height: 16),
                Text(_c.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final busy = _c.isBusy;
    return Scaffold(
      appBar: AppBar(
        title: Text(_c.isPersisted ? 'Edit Test' : 'Create Test'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: busy ? null : () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          _stepIndicator(),
          Expanded(child: _buildStep()),
          _bottomBar(busy),
        ],
      ),
    );
  }

  Widget _stepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < TestCreationScreen.stepTitles.length; i++) ...[
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
            if (i < TestCreationScreen.stepTitles.length - 1)
              const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return BasicDetailsStep(
          title: _c.title,
          description: _c.description,
          kind: _c.kind,
          onTitleChanged: _c.setTitle,
          onDescriptionChanged: _c.setDescription,
          onKindChanged: _c.setKind,
        );
      case 1:
        return ConfigurationStep(
          durationSec: _c.durationSec,
          marksPerQuestion: _c.marksPerQuestion,
          negativeMarks: _c.negativeMarks,
          testMode: _c.kind.requiresGroup
              ? 'group'
              : (_c.kind.supportsCodeEntry ? 'live' : 'self'),
          groupId: _c.groupId,
          startsAt: _c.startsAt,
          endsAt: _c.endsAt,
          maxParticipants: _c.maxParticipants,
          allowLateJoin: _c.allowLateJoin,
          accessCode: _c.accessCode,
          joinCode: _c.joinCode,
          attemptSettings: _c.attemptSettings,
          kind: _c.kind,
          lateJoin: _c.lateJoin,
          questionConfig: _c.questionConfig,
          groups: _c.groups,
          onChanged: (v) => _c.setConfiguration(
            durationSec: v['durationSec'] as int?,
            marksPerQuestion: v['marksPerQuestion'] as double?,
            negativeMarks: v['negativeMarks'] as double?,
            groupId: v['groupId'] as String?,
            startsAt: v['startsAt'] as DateTime?,
            endsAt: v['endsAt'] as DateTime?,
            maxParticipants: v['maxParticipants'] as int?,
            allowLateJoin: v['allowLateJoin'] as bool? ?? false,
            accessCode: v['accessCode'] as String?,
            joinCode: v['joinCode'] as String?,
            attemptSettings: v['attemptSettings'] as AttemptSettings?,
            lateJoin: v['lateJoin'] as LateJoinSettings?,
            questionConfig: v['questionConfig'] as QuestionConfig?,
          ),
        );
      case 2:
        return StepSyllabus(
          selectedNodeIds: _c.syllabusNodeIds,
          serverSelectedNodeIds: _c.serverSyllabusNodeIds,
          onChanged: _c.setSyllabusNodeIds,
        );
      case 3:
        return QuestionSourceStep(
          selected: _source,
          onChanged: (s) => setState(() => _source = s),
        );
      case 4:
        return QuestionsStep(
          localQuestions: _c.localQuestions,
          serverQuestions: _c.serverQuestions,
          onLocalQuestionsChanged: _c.setLocalQuestions,
          onDeleteServerQuestion: (q) => _c.deleteServerQuestion(q.id),
          onUpdateServerQuestion: _c.updateServerQuestion,
          guidance: _c.questionsGuidance,
          busy: _c.isBusy,
        );
      default:
        return ReviewStep(
          title: _c.title,
          kind: _c.kind,
          durationSec: _c.durationSec,
          marksPerQuestion: _c.marksPerQuestion,
          negativeMarks: _c.negativeMarks,
          startsAt: _c.startsAt,
          endsAt: _c.calculatedEndsAt,
          readiness: _c.readiness,
          extraRows: [
            if (_c.questionConfig.isSet)
              ('Difficulty target', _c.distributionCheck?.summary ?? ''),
            (
              'Attempts',
              _c.attemptSettings.allowReattempt
                  ? 'Re-attempt allowed, max ${_c.attemptSettings.effectiveMax}'
                  : 'Single attempt',
            ),
            if (_c.kind.supportsLateJoin)
              (
                'Late joining',
                _c.lateJoin.enabled
                    ? 'Allowed for ${_c.lateJoin.minutes} min after start'
                    : 'Not allowed',
              ),
            ('Question source', _source.label),
          ],
          serverQuestions: _c.serverQuestions,
          localQuestions: _c.localQuestions,
          syllabusCount: _c.syllabusNodeIds.length,
          onApprove: _c.approveQuestion,
          onApproveAll: _c.approveAllPending,
          busy: _c.isBusy,
        );
    }
  }

  Widget _bottomBar(bool busy) {
    final last = _step == TestCreationScreen.stepTitles.length - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_step > 0)
              OutlinedButton(
                onPressed: busy ? null : () => setState(() => _step--),
                child: const Text('Back'),
              ),
            const Spacer(),
            if (!last)
              FilledButton(
                onPressed: busy || !_canProceed
                    ? null
                    : () => setState(() => _step++),
                child: const Text('Next'),
              )
            else ...[
              OutlinedButton(
                onPressed: busy ? null : _saveDraft,
                child: Text(busy ? 'Saving…' : 'Save Draft'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : _publish,
                child: const Text('Publish'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
