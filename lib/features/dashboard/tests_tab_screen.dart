import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/test.dart';
import '../test/domain/backend_mapping.dart';
import '../test/domain/test_lifecycle.dart';
import '../test/state/test_listing_controller.dart';
import '../test/widgets/test_formatters.dart';

/// Tests tab: an at-a-glance summary (upcoming, challenges, drafts) backed
/// by the same [TestListingController] the full `/tests` screen uses. Every
/// card and the FAB reuse the existing test routes.
class TestsTabScreen extends StatefulWidget {
  const TestsTabScreen({super.key});

  @override
  State<TestsTabScreen> createState() => _TestsTabScreenState();
}

class _TestsTabScreenState extends State<TestsTabScreen> {
  late final TestListingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TestListingController();
    _controller.addListener(_onChanged);
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/tests/create');
          if (mounted) _controller.refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Test'),
      ),
      body: RefreshIndicator(
        onRefresh: _controller.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(
                context,
                title: 'Upcoming',
                category: ListingCategory.upcoming,
                onViewAll: () => context.push('/tests'),
              ),
              const SizedBox(height: 20),
              _section(
                context,
                title: 'Challenge with Friends',
                category: ListingCategory.challengeWithFriends,
                onViewAll: () => context.push('/tests?tab=1'),
              ),
              const SizedBox(height: 20),
              _draftsRow(context),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Previous Tests'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tests?tab=2'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('Templates'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tests/templates'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _draftsRow(BuildContext context) {
    final count = _controller.hasLoaded ? _controller.draftsAll.length : null;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.drafts_outlined),
        title: const Text('My Drafts'),
        subtitle: Text(count == null ? 'Loading…' : '$count draft${count == 1 ? '' : 's'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/tests/drafts'),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required ListingCategory category,
    required VoidCallback onViewAll,
  }) {
    Widget body;
    if (!_controller.hasLoaded && _controller.isLoading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_controller.error != null) {
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(_controller.error!)),
              TextButton(onPressed: _controller.refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    } else {
      final tests = _controller.testsFor(category).take(3).toList();
      if (tests.isEmpty) {
        body = Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No tests here yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ),
        );
      } else {
        body = Column(children: [for (final t in tests) _TestCard(test: t)]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            TextButton(onPressed: onViewAll, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test});

  final Test test;

  @override
  Widget build(BuildContext context) {
    final kind = BackendMapping.fromBackend(test.testMode, test.settings);
    final statusColor = TestFormatters.statusColor(test.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/tests/${test.id}'),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      TestLifecycle.statusLabel(test.status),
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(kind.label, style: Theme.of(context).textTheme.bodySmall),
                  Text(TestFormatters.duration(test.durationSec), style: Theme.of(context).textTheme.bodySmall),
                  if (test.startsAt != null)
                    Text(TestFormatters.dateTime(test.startsAt), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
