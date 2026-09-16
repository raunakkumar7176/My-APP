import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/test.dart';
import '../../core/services/test_service.dart';
import 'widgets/join_with_code_sheet.dart';

enum TestCategory { upcoming, challengeWithFriends, previous, myDrafts }

class TestListingScreen extends StatefulWidget {
  const TestListingScreen({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  State<TestListingScreen> createState() => _TestListingScreenState();
}

class _TestListingScreenState extends State<TestListingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Test> _allTests = [];
  List<Test> _myDrafts = [];
  bool _isLoading = true;
  bool _isLoadingDrafts = false;
  String? _error;
  String? _draftsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (widget.initialTab > 0 && widget.initialTab < 4) {
      _tabController.index = widget.initialTab;
    }
    _loadTests();
    _loadDrafts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      AppLogger.info('_loadTests: calling getAccessibleTests');
      final tests = await TestService.getAccessibleTests(limit: 100);
      AppLogger.info('_loadTests: got ${tests.length} tests');
      if (mounted) {
        setState(() {
          _allTests = tests;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error(
          '_loadTests: error runtimeType=${e.runtimeType}, error=$e',
          stackTrace: st);
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('AppError: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDrafts() async {
    setState(() {
      _isLoadingDrafts = true;
      _draftsError = null;
    });

    try {
      AppLogger.info('_loadDrafts: calling getMyDrafts');
      final drafts = await TestService.getMyDrafts(limit: 50);
      AppLogger.info('_loadDrafts: got ${drafts.length} drafts');
      if (mounted) {
        setState(() {
          _myDrafts = drafts;
          _isLoadingDrafts = false;
        });
      }
    } catch (e, st) {
      AppLogger.error(
          '_loadDrafts: error runtimeType=${e.runtimeType}, error=$e, displayed="${e.toString().replaceFirst('AppError: ', '')}"',
          stackTrace: st);
      if (mounted) {
        setState(() {
          _draftsError = e.toString().replaceFirst('AppError: ', '');
          _isLoadingDrafts = false;
        });
      }
    }
  }

  /// Pushes [location] and reloads both lists when the user comes back, so a
  /// draft saved/edited/published on the pushed screen is visible without
  /// pull-to-refresh. (Publish uses context.go('/tests'), which rebuilds the
  /// screen anyway; this covers the pop-back paths.)
  Future<void> _pushThenRefresh(String location, {Object? extra}) async {
    await context.push(location, extra: extra);
    if (mounted) await _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadTests(), _loadDrafts()]);
  }

  List<Test> _getTestsForCategory(TestCategory category) {
    final now = DateTime.now();
    return _allTests.where((test) {
      if (test.isSoftDeleted) return false;

      switch (category) {
        case TestCategory.upcoming:
          return _isUpcoming(test, now);
        case TestCategory.challengeWithFriends:
          return _isChallengeWithFriends(test, now);
        case TestCategory.previous:
          return _isPrevious(test, now);
        case TestCategory.myDrafts:
          return false;
      }
    }).toList();
  }

  bool _isUpcoming(Test test, DateTime now) {
    switch (test.status) {
      case TestStatus.scheduled:
        return true;
      case TestStatus.published:
        if (test.startsAt != null && test.startsAt!.isAfter(now)) {
          return true;
        }
        if (test.testMode == 'self' || test.testMode == 'group') {
          final ended = test.endsAt != null && test.endsAt!.isBefore(now);
          return !ended;
        }
        return false;
      default:
        return false;
    }
  }

  bool _isChallengeWithFriends(Test test, DateTime now) {
    if (test.testMode != 'live') return false;
    switch (test.status) {
      case TestStatus.live:
      case TestStatus.ready:
        return true;
      case TestStatus.published:
        if (test.startsAt != null && test.startsAt!.isAfter(now)) {
          return false;
        }
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return false;
        }
        return true;
      case TestStatus.scheduled:
        return false;
      default:
        return false;
    }
  }

  bool _isPrevious(Test test, DateTime now) {
    switch (test.status) {
      case TestStatus.completed:
      case TestStatus.ended:
      case TestStatus.evaluated:
      case TestStatus.cancelled:
      case TestStatus.archived:
      case TestStatus.expired:
        return true;
      case TestStatus.published:
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return true;
        }
        return false;
      case TestStatus.live:
      case TestStatus.ready:
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '--';
    final minutes = seconds ~/ 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return remainingMinutes > 0
          ? '${hours}h ${remainingMinutes}m'
          : '${hours}h';
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
        title: const Text('Tests'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Challenge with Friends'),
            Tab(text: 'Previous'),
            Tab(text: 'My Drafts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTestTab(TestCategory.upcoming),
          _buildTestTab(TestCategory.challengeWithFriends),
          _buildTestTab(TestCategory.previous),
          _buildDraftsTab(),
        ],
      ),
    );
  }

  Widget _buildTestTab(TestCategory category) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState(_error!, _loadTests);
    }

    final tests = _getTestsForCategory(category);

    final body = tests.isEmpty
        ? _buildEmptyState(category)
        : RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tests.length,
              itemBuilder: (context, index) {
                return _buildTestCard(tests[index]);
              },
            ),
          );

    if (category != TestCategory.challengeWithFriends) return body;

    // Challenge with Friends can also be entered with a code shared by the
    // creator (rpc_start_attempt_by_code) — such tests may not be listed.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => JoinWithCodeSheet.show(context),
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              label: const Text('Join with code'),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildDraftsTab() {
    if (_isLoadingDrafts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_draftsError != null) {
      return _buildErrorState(_draftsError!, _loadDrafts);
    }

    if (_myDrafts.isEmpty) {
      return _buildDraftsEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myDrafts.length,
        itemBuilder: (context, index) {
          return _buildDraftCard(_myDrafts[index]);
        },
      ),
    );
  }

  Widget _buildErrorState(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(TestCategory category) {
    String title;
    String subtitle;
    IconData icon;

    switch (category) {
      case TestCategory.upcoming:
        title = 'No upcoming tests';
        subtitle = 'Tests scheduled for the future will appear here.';
        icon = Icons.event_outlined;
        break;
      case TestCategory.challengeWithFriends:
        title = 'No active challenges';
        subtitle = 'Tests shared with friends will appear here.';
        icon = Icons.people_outline;
        break;
      case TestCategory.previous:
        title = 'No previous tests';
        subtitle = 'Completed or ended tests will appear here.';
        icon = Icons.history;
        break;
      case TestCategory.myDrafts:
        title = 'No drafts yet';
        subtitle = 'Create a test to get started.';
        icon = Icons.drafts_outlined;
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.drafts_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No drafts yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a test and save as draft to continue editing later.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _pushThenRefresh('/create-test'),
              icon: const Icon(Icons.add),
              label: const Text('Create Test'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard(Test test) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/test-detail', extra: test),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      test.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(test.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getStatusText(test.status),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _getStatusColor(test.status),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (test.description != null && test.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  test.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    Icons.timer_outlined,
                    _formatDuration(test.durationSec),
                  ),
                  if (test.testMode != null)
                    _buildInfoChip(
                      _getTestModeIcon(test.testMode!),
                      test.typeLabel,
                    ),
                  if (test.totalQuestions != null && test.totalQuestions! > 0)
                    _buildInfoChip(
                      Icons.question_answer_outlined,
                      '${test.totalQuestions} Q',
                    ),
                  if (test.marksPerQuestion != null)
                    _buildInfoChip(
                      Icons.star_outline,
                      '${test.marksPerQuestion} marks/Q',
                    ),
                ],
              ),
              if (test.startsAt != null || test.endsAt != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (test.startsAt != null) ...[
                      Icon(
                        Icons.play_arrow,
                        size: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateTime(test.startsAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                      ),
                    ],
                    if (test.startsAt != null && test.endsAt != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (test.endsAt != null) ...[
                      Icon(
                        Icons.stop,
                        size: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateTime(test.endsAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraftCard(Test test) {
    final now = DateTime.now();
    final ageText = _getDraftAge(test.updatedAt ?? test.createdAt, now);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _pushThenRefresh('/edit-test/${test.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      test.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Draft',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (test.description != null && test.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  test.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(
                    Icons.timer_outlined,
                    _formatDuration(test.durationSec),
                  ),
                  const SizedBox(width: 16),
                  _buildInfoChip(
                    Icons.question_answer_outlined,
                    '${test.totalQuestions ?? 0} Q',
                  ),
                  const Spacer(),
                  if (ageText.isNotEmpty)
                    Text(
                      ageText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pushThenRefresh('/edit-test/${test.id}'),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Continue Editing'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _pushThenRefresh('/test-detail', extra: test),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Preview'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDraftAge(DateTime? dateTime, DateTime now) {
    if (dateTime == null) return '';
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
      ],
    );
  }

  IconData _getTestModeIcon(String mode) {
    switch (mode) {
      case 'self':
        return Icons.person_outline;
      case 'live':
        return Icons.people_outline;
      case 'group':
        return Icons.group_outlined;
      default:
        return Icons.help_outline;
    }
  }

}
