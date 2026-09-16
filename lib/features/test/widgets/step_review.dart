import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/question.dart';
import '../../../core/models/test_kind.dart';
import '../../../core/services/question_service.dart';
import '../models/question_draft.dart';

class StepReview extends StatefulWidget {
  const StepReview({
    required this.title,
    required this.description,
    required this.durationSec,
    required this.marksPerQuestion,
    required this.negativeMarks,
    required this.testMode,
    this.groupId,
    required this.startsAt,
    required this.endsAt,
    required this.maxParticipants,
    required this.allowLateJoin,
    required this.accessCode,
    required this.joinCode,
    required this.questions,
    required this.serverQuestions,
    required this.syllabusNodeIds,
    required this.serverSyllabusNodeIds,
    required this.onServerQuestionUpdated,
    this.testKind = TestKind.self,
    super.key,
  });

  final String title;
  final String description;
  final int? durationSec;
  final double? marksPerQuestion;
  final double? negativeMarks;
  final String? testMode;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxParticipants;
  final bool allowLateJoin;
  final String? accessCode;
  final String? joinCode;
  final String? groupId;
  final List<QuestionDraft> questions;
  final List<Question> serverQuestions;
  final List<String> syllabusNodeIds;
  final List<String> serverSyllabusNodeIds;

  /// Called after a server question's status changed on the server (e.g.
  /// approved) so the parent can replace it in its list and re-evaluate
  /// publish readiness. `Question` is immutable, so the parent's list is the
  /// only place the new status can live.
  final ValueChanged<Question> onServerQuestionUpdated;

  /// Self-family kind shown in the summary (ignored for other modes).
  final TestKind testKind;

  @override
  State<StepReview> createState() => _StepReviewState();
}

class _StepReviewState extends State<StepReview> {
  bool _isApproving = false;

  int get _totalQuestions =>
      widget.questions.length + widget.serverQuestions.length;

  int get _totalMarks {
    int total = 0;
    for (final q in widget.serverQuestions) {
      total += q.marks;
    }
    for (final q in widget.questions) {
      total += q.marks;
    }
    return total;
  }

  int get _totalSyllabus =>
      widget.syllabusNodeIds.length + widget.serverSyllabusNodeIds.length;

  bool get _allServerQuestionsApproved {
    return widget.serverQuestions.every((q) => q.status == 'approved');
  }

  bool get _allQuestionsReady {
    if (_totalQuestions == 0) return false;
    if (widget.serverQuestions.isNotEmpty && !_allServerQuestionsApproved)
      return false;
    return true;
  }

  int get _pendingServerCount =>
      widget.serverQuestions.where((q) => q.status != 'approved').length;

  String get _testModeLabel {
    switch (widget.testMode) {
      case 'self':
      case 'live':
      case 'group':
        return testTypeLabel(testMode: widget.testMode, kind: widget.testKind);
      default:
        return 'Not set';
    }
  }

  Future<void> _approveQuestion(Question question) async {
    if (_isApproving) return;
    setState(() => _isApproving = true);
    try {
      await QuestionService.approveQuestion(question.id);
      widget.onServerQuestionUpdated(question.copyWith(status: 'approved'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Question approved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to approve question: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  // ─── PUBLISH READINESS ──────────────────────────────────────

  List<_ReadinessItem> _getReadinessItems() {
    final items = <_ReadinessItem>[];

    items.add(
      _ReadinessItem(
        label: 'Test title',
        isValid: widget.title.trim().isNotEmpty,
        invalidReason: widget.title.trim().isEmpty
            ? 'Enter a test title'
            : null,
      ),
    );

    items.add(
      _ReadinessItem(
        label: 'Duration set',
        isValid: widget.durationSec != null && widget.durationSec! > 0,
        invalidReason: widget.durationSec == null || widget.durationSec! <= 0
            ? 'Set a valid duration'
            : null,
      ),
    );

    items.add(
      _ReadinessItem(
        label: 'Scoring configured',
        isValid:
            widget.marksPerQuestion != null && widget.marksPerQuestion! > 0,
        invalidReason:
            widget.marksPerQuestion == null || widget.marksPerQuestion! <= 0
            ? 'Set marks per question'
            : null,
      ),
    );

    items.add(
      _ReadinessItem(
        label: 'Test mode selected',
        isValid: widget.testMode != null,
        invalidReason: widget.testMode == null ? 'Select a test mode' : null,
      ),
    );

    final isGroupMode = widget.testMode == 'group';
    if (isGroupMode) {
      items.add(
        _ReadinessItem(
          label: 'Group selected',
          isValid: widget.groupId != null && widget.groupId!.isNotEmpty,
          invalidReason: 'Select a group for Group Test',
        ),
      );
    }

    final hasQuestions = _totalQuestions > 0;
    items.add(
      _ReadinessItem(
        label: 'Questions added',
        isValid: hasQuestions,
        invalidReason: hasQuestions ? null : 'Add at least one question',
      ),
    );

    if (hasQuestions) {
      final allApproved = _allQuestionsReady;
      items.add(
        _ReadinessItem(
          label: 'All questions approved',
          isValid: allApproved,
          invalidReason: allApproved
              ? null
              : '$_pendingServerCount question(s) need approval',
        ),
      );
    }

    if (widget.questions.isNotEmpty) {
      int invalidCount = 0;
      for (final draft in widget.questions) {
        if (!draft.isValid) invalidCount++;
      }
      items.add(
        _ReadinessItem(
          label: 'All questions valid',
          isValid: invalidCount == 0,
          invalidReason: invalidCount > 0
              ? '$invalidCount question(s) need fixing'
              : null,
        ),
      );
    }

    items.add(
      const _ReadinessItem(label: 'Syllabus references', isValid: true),
    );

    bool timingValid = true;
    String? timingReason;
    if (widget.startsAt != null && widget.endsAt != null) {
      if (widget.endsAt!.isBefore(widget.startsAt!)) {
        timingValid = false;
        timingReason = 'End time must be after start time';
      }
    }
    items.add(
      _ReadinessItem(
        label: 'Schedule valid',
        isValid: timingValid,
        invalidReason: timingReason,
      ),
    );

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final readinessItems = _getReadinessItems();
    final readyCount = readinessItems.where((i) => i.isValid).length;
    final totalCount = readinessItems.length;
    final allReady = readyCount == totalCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Test',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Review your test details before publishing.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // ─── PUBLISH READINESS CHECKLIST ─────────────────────
          _buildSection(
            context,
            title: 'Publish Readiness',
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totalCount > 0 ? readyCount / totalCount : 0,
                        minHeight: 6,
                        backgroundColor: AppColors.textSecondaryLight
                            .withValues(alpha: 0.2),
                        color: allReady
                            ? AppColors.success
                            : AppColors.primaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$readyCount/$totalCount',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: allReady
                          ? AppColors.success
                          : AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...readinessItems.map(
                (item) => _buildReadinessItem(context, item),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ─── BASIC DETAILS ───────────────────────────────────
          _buildSection(
            context,
            title: 'Basic Details',
            children: [
              _buildRow(context, 'Title', widget.title),
              if (widget.description.isNotEmpty)
                _buildRow(context, 'Description', widget.description),
            ],
          ),
          const SizedBox(height: 16),

          // ─── CONFIGURATION ──────────────────────────────────
          _buildSection(
            context,
            title: 'Configuration',
            children: [
              _buildRow(
                context,
                'Duration',
                widget.durationSec != null
                    ? '${widget.durationSec! ~/ 60} minutes'
                    : 'Not set',
              ),
              _buildRow(
                context,
                'Marks per Question',
                widget.marksPerQuestion?.toString() ?? 'Not set',
              ),
              _buildRow(
                context,
                'Negative Marks',
                widget.negativeMarks?.toString() ?? 'None',
              ),
              _buildRow(context, 'Test Type', _testModeLabel),
            ],
          ),
          const SizedBox(height: 16),

          // ─── SCHEDULE ───────────────────────────────────────
          _buildSection(
            context,
            title: 'Schedule',
            children: [
              _buildRow(
                context,
                'Start Time',
                widget.startsAt != null
                    ? '${widget.startsAt!.day}/${widget.startsAt!.month}/${widget.startsAt!.year} ${widget.startsAt!.hour}:${widget.startsAt!.minute.toString().padLeft(2, '0')}'
                    : 'Not scheduled',
              ),
              _buildRow(
                context,
                'End Time',
                widget.endsAt != null
                    ? '${widget.endsAt!.day}/${widget.endsAt!.month}/${widget.endsAt!.year} ${widget.endsAt!.hour}:${widget.endsAt!.minute.toString().padLeft(2, '0')}'
                    : 'Not scheduled',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── ACCESS CONTROL ─────────────────────────────────
          _buildSection(
            context,
            title: 'Access Control',
            children: [
              _buildRow(
                context,
                'Max Participants',
                widget.maxParticipants?.toString() ?? 'Unlimited',
              ),
              _buildRow(
                context,
                'Allow Late Join',
                widget.allowLateJoin ? 'Yes' : 'No',
              ),
              _buildRow(
                context,
                'Access Code',
                widget.accessCode?.isNotEmpty == true ? 'Set' : 'Not set',
              ),
              _buildRow(
                context,
                'Join Code',
                widget.joinCode?.isNotEmpty == true ? 'Set' : 'Not set',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── QUESTIONS ──────────────────────────────────────
          _buildSection(
            context,
            title: 'Questions',
            children: [
              _buildRow(context, 'Total Questions', '$_totalQuestions'),
              _buildRow(context, 'Total Marks', '$_totalMarks'),
              if (_totalQuestions > 0) ...[
                const SizedBox(height: 8),
                _buildQuestionTypeBreakdown(context),
                const SizedBox(height: 12),
                _buildQuestionApprovalSection(context),
              ],
            ],
          ),

          if (_totalSyllabus > 0) ...[
            const SizedBox(height: 16),
            _buildSection(
              context,
              title: 'Syllabus',
              children: [
                _buildRow(
                  context,
                  'Topics Selected',
                  '$_totalSyllabus topic(s)',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── QUESTION APPROVAL SECTION ──────────────────────────────

  Widget _buildQuestionApprovalSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Approval Status',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_pendingServerCount > 0)
              TextButton.icon(
                onPressed: _isApproving ? null : _approveAllPending,
                icon: _isApproving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Approve All'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...widget.serverQuestions.map(
          (q) => _buildQuestionApprovalTile(context, q),
        ),
        ...widget.questions.map((d) => _buildDraftApprovalTile(context, d)),
      ],
    );
  }

  Widget _buildQuestionApprovalTile(BuildContext context, Question question) {
    final isApproved = question.status == 'approved';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isApproved ? Icons.check_circle : Icons.pending,
            size: 18,
            color: isApproved ? AppColors.success : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q${question.ordinal ?? '?'}: ${question.question}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  isApproved ? 'Approved' : 'Pending Review',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isApproved ? AppColors.success : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!isApproved)
            TextButton(
              onPressed: _isApproving ? null : () => _approveQuestion(question),
              child: const Text('Approve'),
            ),
        ],
      ),
    );
  }

  Widget _buildDraftApprovalTile(BuildContext context, QuestionDraft draft) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            draft.isValid ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: draft.isValid ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Draft: ${draft.questionText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  draft.isValid
                      ? 'Valid (will be approved on publish)'
                      : 'Invalid — fix before publishing',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: draft.isValid ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveAllPending() async {
    if (_isApproving) return;
    setState(() => _isApproving = true);

    int approved = 0;
    int failed = 0;

    // Iterate over a snapshot: each callback replaces an entry in the
    // parent's list, which is the same list instance as widget.serverQuestions.
    for (final q in List<Question>.from(widget.serverQuestions)) {
      if (q.status != 'approved') {
        try {
          await QuestionService.approveQuestion(q.id);
          widget.onServerQuestionUpdated(q.copyWith(status: 'approved'));
          approved++;
        } catch (e) {
          AppLogger.error('Failed to approve question ${q.id}: $e');
          failed++;
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed > 0
                ? 'Approved $approved, failed $failed'
                : 'All $approved question(s) approved',
          ),
          backgroundColor: failed > 0 ? Colors.orange : AppColors.success,
        ),
      );
      setState(() => _isApproving = false);
    }
  }

  Widget _buildReadinessItem(BuildContext context, _ReadinessItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isValid ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: item.isValid ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: item.isValid
                        ? Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.8)
                        : AppColors.error,
                  ),
                ),
                if (item.invalidReason != null)
                  Text(
                    item.invalidReason!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionTypeBreakdown(BuildContext context) {
    int mcqCount = 0;
    int tfCount = 0;
    int numCount = 0;
    int shortCount = 0;

    for (final q in widget.serverQuestions) {
      switch (q.questionType) {
        case QuestionType.mcqSingle:
        case QuestionType.mcqMultiple:
          mcqCount++;
          break;
        case QuestionType.trueFalse:
          tfCount++;
          break;
        case QuestionType.integer:
          numCount++;
          break;
        case QuestionType.shortAnswer:
          shortCount++;
          break;
        default:
          mcqCount++;
      }
    }

    for (final q in widget.questions) {
      switch (q.questionType) {
        case QuestionType.mcqSingle:
        case QuestionType.mcqMultiple:
          mcqCount++;
          break;
        case QuestionType.trueFalse:
          tfCount++;
          break;
        case QuestionType.integer:
          numCount++;
          break;
        case QuestionType.shortAnswer:
          shortCount++;
          break;
        default:
          mcqCount++;
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (mcqCount > 0) _buildChip(context, 'MCQ: $mcqCount'),
        if (tfCount > 0) _buildChip(context, 'True/False: $tfCount'),
        if (numCount > 0) _buildChip(context, 'Numeric: $numCount'),
        if (shortCount > 0) _buildChip(context, 'Short: $shortCount'),
      ],
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
    );
  }
}

class _ReadinessItem {
  final String label;
  final bool isValid;
  final String? invalidReason;

  const _ReadinessItem({
    required this.label,
    required this.isValid,
    this.invalidReason,
  });
}
