import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/errors/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/result_batch.dart';
import '../../core/models/test.dart';
import '../../core/services/attempt_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/batch_result_service.dart';
import '../../core/services/question_service.dart';
import '../../core/services/test_service.dart';

class TestDetailScreen extends StatefulWidget {
  const TestDetailScreen({required this.test, super.key});

  final Test test;

  @override
  State<TestDetailScreen> createState() => _TestDetailScreenState();
}

class _TestDetailScreenState extends State<TestDetailScreen> {
  ResultBatch? _latestBatch;
  bool _isLoadingBatch = false;
  bool _isGenerating = false;
  bool _isStarting = false;
  bool _isPublishing = false;

  /// The test as passed in via the route (instant render), replaced by the
  /// server row once [_refreshTest] completes so status/timing-dependent
  /// actions (Start, Publish, Generate Results) are not based on stale data.
  late Test _test = widget.test;
  Test get test => _test;

  @override
  void initState() {
    super.initState();
    _refreshTest();
    _loadBatchStatus();
  }

  Future<void> _refreshTest() async {
    try {
      final fresh = await TestService.getTestById(widget.test.id);
      if (fresh != null && mounted) setState(() => _test = fresh);
    } catch (e) {
      // Keep rendering the passed-in object; server checks remain
      // authoritative for every action anyway.
      AppLogger.warning('Test detail refresh failed: $e');
    }
  }

  Future<void> _loadBatchStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingBatch = true);
    try {
      final batch = await BatchResultService.getLatestBatch(test.id);
      if (!mounted) return;
      setState(() => _latestBatch = batch);
    } catch (e) {
      AppLogger.error('Failed to load batch status: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBatch = false);
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '--';
    final minutes = seconds ~/ 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return remainingMinutes > 0 ? '${hours}h ${remainingMinutes}m' : '${hours}h';
    }
    return '${minutes}m';
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '--';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(TestStatus status) {
    switch (status) {
      case TestStatus.scheduled:
        return AppColors.warning;
      case TestStatus.live:
      case TestStatus.ready:
        return AppColors.success;
      case TestStatus.completed:
      case TestStatus.ended:
      case TestStatus.evaluated:
        return AppColors.primaryLight;
      case TestStatus.cancelled:
      case TestStatus.expired:
        return AppColors.error;
      case TestStatus.draft:
      case TestStatus.published:
      case TestStatus.archived:
      case TestStatus.unknown:
        return AppColors.textSecondaryLight;
    }
  }

  String _getStatusText(TestStatus status) {
    switch (status) {
      case TestStatus.draft:
        return 'Draft';
      case TestStatus.scheduled:
        return 'Scheduled';
      case TestStatus.live:
        return 'Ongoing';
      case TestStatus.ready:
        return 'Ready';
      case TestStatus.published:
        return 'Published';
      case TestStatus.completed:
        return 'Completed';
      case TestStatus.ended:
        return 'Ended';
      case TestStatus.evaluated:
        return 'Evaluated';
      case TestStatus.cancelled:
        return 'Cancelled';
      case TestStatus.archived:
        return 'Archived';
      case TestStatus.expired:
        return 'Expired';
      case TestStatus.unknown:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Details'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildStatusSection(context),
            const SizedBox(height: 16),
            _buildConfigurationSection(context),
            const SizedBox(height: 16),
            _buildScheduleSection(context),
            const SizedBox(height: 16),
            _buildScoringSection(context),
            const SizedBox(height: 16),
            if (test.groupId != null) ...[
              _buildGroupSection(context),
              const SizedBox(height: 16),
            ],
            if (test.joinCode != null || test.accessCode != null) ...[
              _buildAccessCodeSection(context),
              const SizedBox(height: 16),
            ],
            _buildBatchSection(context),
            const SizedBox(height: 16),
            _buildActionSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          test.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (test.description != null && test.description!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            test.description!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(test.status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _getStatusText(test.status),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _getStatusColor(test.status),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              test.testMode == null ? '--' : test.typeLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationSection(BuildContext context) {
    return _buildSection(
      context,
      title: 'Configuration',
      children: [
        _buildDetailRow(context, icon: Icons.timer_outlined, label: 'Duration', value: _formatDuration(test.durationSec)),
        if (test.totalQuestions != null && test.totalQuestions! > 0)
          _buildDetailRow(context, icon: Icons.question_answer_outlined, label: 'Questions', value: '${test.totalQuestions}'),
        if (test.maxParticipants != null)
          _buildDetailRow(context, icon: Icons.people_outlined, label: 'Max Participants', value: '${test.maxParticipants}'),
        if (test.allowLateJoin)
          _buildDetailRow(context, icon: Icons.login, label: 'Late Join', value: 'Allowed'),
        if (test.shuffleQuestions)
          _buildDetailRow(context, icon: Icons.shuffle, label: 'Shuffle', value: 'Enabled'),
        if (test.showAnswersAfter)
          _buildDetailRow(context, icon: Icons.visibility_outlined, label: 'Show Answers', value: 'After Submission'),
      ],
    );
  }

  Widget _buildScheduleSection(BuildContext context) {
    return _buildSection(
      context,
      title: 'Schedule',
      children: [
        _buildDetailRow(context, icon: Icons.play_arrow, label: 'Start Time', value: _formatDateTime(test.startsAt)),
        _buildDetailRow(context, icon: Icons.stop, label: 'End Time', value: _formatDateTime(test.endsAt)),
      ],
    );
  }

  Widget _buildScoringSection(BuildContext context) {
    return _buildSection(
      context,
      title: 'Scoring',
      children: [
        if (test.marksPerQuestion != null)
          _buildDetailRow(context, icon: Icons.star_outline, label: 'Marks per Question', value: '${test.marksPerQuestion}'),
        if (test.negativeMarks != null && test.negativeMarks! > 0)
          _buildDetailRow(context, icon: Icons.remove_circle_outline, label: 'Negative Marks', value: '${test.negativeMarks}'),
        if (test.totalMarks != null && test.totalMarks! > 0)
          _buildDetailRow(context, icon: Icons.grade_outlined, label: 'Total Marks', value: '${test.totalMarks}'),
        if (test.passingMarks != null && test.passingMarks! > 0)
          _buildDetailRow(context, icon: Icons.check_circle_outline, label: 'Passing Marks', value: '${test.passingMarks}'),
      ],
    );
  }

  Widget _buildGroupSection(BuildContext context) {
    return _buildSection(
      context,
      title: 'Group',
      children: [
        _buildDetailRow(context, icon: Icons.group_outlined, label: 'Group', value: test.groupId ?? '--'),
      ],
    );
  }

  Widget _buildAccessCodeSection(BuildContext context) {
    return _buildSection(
      context,
      title: 'Access Codes',
      children: [
        if (test.accessCode != null)
          _buildDetailRow(context, icon: Icons.vpn_key_outlined, label: 'Access Code', value: 'Set'),
        if (test.joinCode != null)
          _buildDetailRow(context, icon: Icons.pin_outlined, label: 'Join Code', value: test.joinCode!),
      ],
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, {required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            )),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ─── OWNERSHIP / PERMISSIONS ──────────────────────────────────

  bool get _isOwner {
    final currentUser = AuthService.currentUser;
    return currentUser != null && test.createdBy == currentUser.id;
  }

  // Only drafts: the creation screen (/edit-test/:id) rejects any other
  // status ("Only draft tests can be edited"), so offering Edit for
  // published/scheduled tests was a dead end. Editing published tests is
  // a separate, unimplemented feature.
  bool get _canEdit => _isOwner && test.status == TestStatus.draft;

  bool get _canPublish {
    return _isOwner && test.status == TestStatus.draft;
  }

  String? _getStartTestDisabledReason() {
    final now = DateTime.now();
    switch (test.status) {
      case TestStatus.draft:
        return 'This test is still a draft.';
      case TestStatus.scheduled:
        if (test.startsAt != null && test.startsAt!.isAfter(now)) {
          return 'Test has not started yet. Starts ${_formatDateTime(test.startsAt)}.';
        }
        return null;
      case TestStatus.published:
        if (test.startsAt != null && test.startsAt!.isAfter(now)) {
          return 'Test has not started yet. Starts ${_formatDateTime(test.startsAt)}.';
        }
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return 'This test has ended.';
        }
        return null;
      case TestStatus.live:
      case TestStatus.ready:
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return 'This test has ended.';
        }
        return null;
      case TestStatus.completed:
      case TestStatus.ended:
      case TestStatus.evaluated:
        return 'This test has ended.';
      case TestStatus.cancelled:
        return 'This test has been cancelled.';
      case TestStatus.archived:
        return 'This test has been archived and is no longer available.';
      case TestStatus.expired:
        return 'This test has expired and is no longer available.';
      case TestStatus.unknown:
        return 'This test is in an unknown state.';
    }
  }

  bool get _canStartTest => _getStartTestDisabledReason() == null;

  // ─── ACTIONS ──────────────────────────────────────────────────

  /// Opens the draft editor and refreshes this screen when the user comes
  /// back, so title/config/status changes made there are not shown stale.
  Future<void> _openEditor(BuildContext context) async {
    await context.push('/edit-test/${test.id}');
    if (mounted) await _refreshTest();
  }

  void _continueEditing(BuildContext context) => _openEditor(context);

  void _editTest(BuildContext context) => _openEditor(context);

  Future<void> _publishTest(BuildContext context) async {
    // Guard against rapid re-taps: device logs showed 4 overlapping
    // rpc_publish_test calls from this button within ~300 ms.
    if (_isPublishing) return;
    setState(() => _isPublishing = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      // publishTest already re-reads the test; the screen navigates away,
      // so no further read is needed here.
      await TestService.publishTest(test.id);
      if (!context.mounted) return;
      scaffold.showSnackBar(
        const SnackBar(content: Text('Test published successfully'), backgroundColor: AppColors.success),
      );
      context.go('/tests');
    } on AppError catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      AppLogger.error('_publishTest unexpected: $e');
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text(TestService.mapPublishError(e.toString())), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _startTest(BuildContext context) async {
    if (_isStarting) return;
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _isStarting = true);
    try {
      final attempt = await AttemptService.startAttempt(test.id);
      final questions = await QuestionService.getQuestionsSafe(testId: test.id);

      if (!context.mounted) return;
      scaffold.hideCurrentSnackBar();

      context.go('/test-taking', extra: {
        'attempt': attempt,
        'questions': questions,
        'test': test,
      });
    } on AppError catch (e) {
      if (!mounted) return;
      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      AppLogger.error('_startTest unexpected: $e');
      if (!mounted) return;
      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
        SnackBar(content: Text(TestService.mapStartAttemptError(e.toString())), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  // ─── ACTION SECTION ──────────────────────────────────────────

  Widget _buildActionSection(BuildContext context) {
    final disabledReason = _getStartTestDisabledReason();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Draft state: Continue Editing + Publish
            if (test.status == TestStatus.draft && _isOwner) ...[
              FilledButton.icon(
                onPressed: () => _continueEditing(context),
                icon: const Icon(Icons.edit),
                label: const Text('Continue Editing'),
              ),
              if (_canPublish) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isPublishing ? null : () => _publishTest(context),
                  icon: _isPublishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish),
                  label: Text(_isPublishing ? 'Publishing...' : 'Publish'),
                ),
              ],
            ]

            // Start Test for active tests
            else if (_canStartTest) ...[
              FilledButton.icon(
                onPressed: _isStarting ? null : () => _startTest(context),
                icon: _isStarting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isStarting ? 'Starting...' : 'Start Test'),
              ),
            ]

            // Disabled Start with reason
            else if (disabledReason != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        disabledReason,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Edit button for non-draft editable states
            if (_canEdit && test.status != TestStatus.draft) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editTest(context),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Test'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── BATCH / RESULTS SECTION ─────────────────────────────────

  bool get _canGenerateResults {
    if (!_isOwner) return false;
    return test.isCompleted || test.status == TestStatus.ended;
  }

  Widget _buildBatchSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Results',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_isLoadingBatch)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Loading batch status...'),
                ],
              )
            else if (_latestBatch == null)
              Text(
                'Results not yet generated.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryLight),
              )
            else ...[
              _buildBatchStatusRow(context, _latestBatch!),
              if (_latestBatch!.isProcessing || _latestBatch!.isPartiallyCompleted) ...[
                const SizedBox(height: 8),
                _buildProgressBar(context, _latestBatch!),
              ],
              if (_latestBatch!.isCompleted) ...[
                const SizedBox(height: 8),
                _buildCompletedSummary(context, _latestBatch!),
              ],
              if (_latestBatch!.isFailed) ...[
                const SizedBox(height: 8),
                Text(
                  _latestBatch!.totals?['error'] as String? ?? 'Generation failed. Please try again.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ],
            ],
            if (isOwner && _canGenerateResults) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isGenerating || !_canTriggerBatch ? null : () => _generateResults(context),
                  icon: _isGenerating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate Results'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get isOwner => _isOwner;

  bool get _canTriggerBatch {
    if (_latestBatch == null) return true;
    return _latestBatch!.canTrigger;
  }

  Widget _buildBatchStatusRow(BuildContext context, ResultBatch batch) {
    final (color, label, icon) = switch (batch.status) {
      BatchStatus.pending => (AppColors.warning, 'Pending', Icons.hourglass_empty),
      BatchStatus.processing => (AppColors.primaryLight, 'Processing...', Icons.sync),
      BatchStatus.partiallyCompleted => (AppColors.warning, 'Partially Completed', Icons.sync_problem),
      BatchStatus.completed => (AppColors.success, 'Results Ready', Icons.check_circle),
      BatchStatus.failed => (AppColors.error, 'Generation Failed', Icons.error),
      BatchStatus.unknown => (AppColors.textSecondaryLight, 'Unknown', Icons.help_outline),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context, ResultBatch batch) {
    final done = batch.reportsDone ?? 0;
    final total = batch.reportsTotal ?? 0;
    final pct = (batch.progress * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: batch.progress,
            minHeight: 6,
            backgroundColor: AppColors.textSecondaryLight.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$done / $total reports ($pct%)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryLight),
        ),
      ],
    );
  }

  Widget _buildCompletedSummary(BuildContext context, ResultBatch batch) {
    final done = batch.reportsDone ?? 0;
    return Text(
      '$done results generated.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.success),
    );
  }

  Future<void> _generateResults(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _isGenerating = true);
    try {
      await BatchResultService.generateResults(test.id);
      if (!mounted) return;
      scaffold.showSnackBar(
        const SnackBar(content: Text('Results generation started.')),
      );
      await _loadBatchStatus();
    } on AppError catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      AppLogger.error('_generateResults unexpected: $e');
      if (!mounted) return;
      scaffold.showSnackBar(
        const SnackBar(content: Text('Failed to generate results. Please try again.'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}
