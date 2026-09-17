import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/test.dart';
import '../domain/backend_mapping.dart';
import '../domain/test_kind.dart';
import '../domain/test_lifecycle.dart';
import '../state/test_listing_controller.dart';
import '../widgets/join_with_code_sheet.dart';
import '../widgets/test_formatters.dart';

/// Tabs: Upcoming · Challenge with Friends · Previous · My Drafts.
/// Navigation passes ids only; the detail/edit screens load fresh data.
class TestListingScreen extends StatefulWidget {
  const TestListingScreen({this.initialTab = 0, this.controller, super.key});

  final int initialTab;

  /// Injectable for tests; defaults to a Supabase-backed controller.
  final TestListingController? controller;

  static const tabs = [
    ListingCategory.upcoming,
    ListingCategory.challengeWithFriends,
    ListingCategory.previous,
    ListingCategory.drafts,
  ];

  static String tabLabel(ListingCategory c) {
    switch (c) {
      case ListingCategory.upcoming:
        return 'Upcoming';
      case ListingCategory.challengeWithFriends:
        return 'Challenge with Friends';
      case ListingCategory.previous:
        return 'Previous';
      case ListingCategory.drafts:
        return 'My Drafts';
      case ListingCategory.hidden:
        return '';
    }
  }

  @override
  State<TestListingScreen> createState() => _TestListingScreenState();
}

class _TestListingScreenState extends State<TestListingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TestListingController _controller;
  late final bool _ownsController;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: TestListingScreen.tabs.length, vsync: this);
    if (widget.initialTab > 0 &&
        widget.initialTab < TestListingScreen.tabs.length) {
      _tabs.index = widget.initialTab;
    }
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TestListingController();
    _controller.addListener(_onChanged);
    _search.text = _controller.query;
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _pushThenRefresh(String location) async {
    await context.push(location);
    if (mounted) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tests'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            for (final c in TestListingScreen.tabs)
              Tab(text: TestListingScreen.tabLabel(c)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pushThenRefresh('/tests/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create Test'),
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [for (final c in TestListingScreen.tabs) _buildTab(c)],
            ),
          ),
        ],
      ),
    );
  }

  /// Search (title / description) + kind chips. Client-side only: it never
  /// widens what RLS returned, it only narrows the loaded lists.
  Widget _filterBar() {
    final selected = _controller.kindFilter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            key: const Key('listing_search'),
            controller: _search,
            onChanged: _controller.setQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search tests',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _controller.query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('listing_search_clear'),
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _controller.setQuery('');
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: const Key('kind_chip_all'),
                  label: const Text('All'),
                  selected: selected == null,
                  onSelected: (_) => _controller.setKindFilter(null),
                ),
              ),
              for (final k in TestKind.creatable)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('kind_chip_${k.name}'),
                    label: Text(k.label),
                    selected: selected == k,
                    onSelected: (on) =>
                        _controller.setKindFilter(on ? k : null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(ListingCategory category) {
    final isDrafts = category == ListingCategory.drafts;
    final error = isDrafts ? _controller.draftsError : _controller.error;

    if (!_controller.hasLoaded && _controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) return _errorState(error);

    final tests = isDrafts
        ? _controller.drafts
        : _controller.testsFor(category);

    final body = RefreshIndicator(
      onRefresh: _controller.refresh,
      child: tests.isEmpty
          ? ListView(
              children: [
                if (_controller.hasActiveFilter &&
                    _controller.unfilteredCount(category) > 0)
                  _noMatchState(category)
                else
                  _emptyState(category),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tests.length,
              itemBuilder: (_, i) => _TestCard(
                test: tests[i],
                onTap: () => _pushThenRefresh(
                  isDrafts
                      ? '/tests/${tests[i].id}/edit'
                      : '/tests/${tests[i].id}',
                ),
              ),
            ),
    );

    if (category != ListingCategory.challengeWithFriends) return body;
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

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _controller.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when the tab has tests but none pass the current search / kind
  /// filter, so the user is not told the tab is empty.
  Widget _noMatchState(ListingCategory category) {
    final hidden = _controller.unfilteredCount(category);
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No tests match',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '$hidden ${hidden == 1 ? 'test is' : 'tests are'} hidden by your search or filter.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const Key('clear_filters'),
            onPressed: () {
              _search.clear();
              _controller.clearFilters();
            },
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ListingCategory category) {
    final (title, subtitle, icon) = switch (category) {
      ListingCategory.upcoming => (
        'No upcoming tests',
        'Published and scheduled tests will appear here.',
        Icons.event_outlined,
      ),
      ListingCategory.challengeWithFriends => (
        'No active challenges',
        'Tests shared with friends will appear here.',
        Icons.people_outline,
      ),
      ListingCategory.previous => (
        'No previous tests',
        'Completed or ended tests will appear here.',
        Icons.history,
      ),
      _ => (
        'No drafts yet',
        'Create a test to get started.',
        Icons.drafts_outlined,
      ),
    };
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.onTap});

  final Test test;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = BackendMapping.fromBackend(test.testMode, test.settings);
    final statusColor = TestFormatters.statusColor(test.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
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
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      TestLifecycle.statusLabel(test.status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _chip(context, Icons.category_outlined, kind.label),
                  _chip(
                    context,
                    Icons.timer_outlined,
                    TestFormatters.duration(test.durationSec),
                  ),
                  if (test.startsAt != null)
                    _chip(
                      context,
                      Icons.schedule,
                      TestFormatters.dateTime(test.startsAt),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
