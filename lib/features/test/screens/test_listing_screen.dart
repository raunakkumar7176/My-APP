import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/test.dart';
import '../../../core/widgets/keep_alive_tab.dart';
import '../domain/backend_mapping.dart';
import '../domain/test_kind.dart';
import '../domain/test_lifecycle.dart';
import '../state/test_listing_controller.dart';
import '../widgets/join_with_code_sheet.dart';
import '../widgets/test_formatters.dart';

/// Test source provenance tag.
enum TestProvenance { myStudy, document, ai, group, standard }

/// Tabs: Upcoming · Challenge with Friends · Previous · My Drafts.
/// Authoritative Test Center unifying study, document intake, AI tests, and challenges.
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(context, isDark),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_test_fab'),
        onPressed: () => _pushThenRefresh('/tests/create'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create Test'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Hero & Quick Actions
                          _buildHeroCard(isDark),
                          const SizedBox(height: 12),

                          // 2. Urgent Attention Banner (if any)
                          _buildAttentionBanner(isDark),

                          // 3. Search & Quick Filters
                          _filterBar(isDark),
                          const SizedBox(height: 8),

                          // 4. Segmented Tab Switcher
                          _buildTabBar(isDark),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabs,
                children: [
                  for (final c in TestListingScreen.tabs)
                    KeepAliveTab(child: _buildTab(c, isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDark) {
    return AppBar(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Test Center',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          Text(
            'Assessments, challenges & practice sets',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          key: const Key('join_challenge_button'),
          tooltip: 'Join with code',
          icon: const Icon(Icons.pin_outlined),
          // Same destination as the Hero card's "Join with code" button —
          // this app used to have two different entry points for the same
          // action (this icon pushed a separate, barren full-page screen;
          // the Hero card opened this sheet), which looked like two
          // unrelated features to a student. One sheet, two doors to it.
          onPressed: () => JoinWithCodeSheet.show(context),
        ),
        IconButton(
          key: const Key('templates_button'),
          tooltip: 'Templates',
          icon: const Icon(Icons.dashboard_outlined),
          onPressed: () => context.push('/tests/templates'),
        ),
        IconButton(
          key: const Key('listing_filter_button'),
          tooltip: 'Filter',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => _showFilterSheet(context, isDark),
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _controller.refresh,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHeroCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x263B82F6)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x4D3B82F6)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.assignment_turned_in_rounded,
                    size: 22,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF2563EB),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Center',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Practice, challenge yourself and track your performance.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Quick Action Strip
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pushThenRefresh('/tests/create'),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text(
                  'Create Test',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/study'),
                icon: const Icon(Icons.menu_book_rounded, size: 15),
                label: const Text(
                  'Practice',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF2563EB),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => JoinWithCodeSheet.show(context),
                icon: const Icon(Icons.vpn_key_outlined, size: 15),
                label: const Text(
                  'Join with code',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF475569),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Urgent attention banner when an active/live test is currently running.
  Widget _buildAttentionBanner(bool isDark) {
    final liveTests = _controller.testsFor(
      ListingCategory.challengeWithFriends,
    );
    final upcomingTests = _controller.testsFor(ListingCategory.upcoming);

    Test? urgent;
    for (final t in liveTests) {
      if (t.status == TestStatus.live || t.status == TestStatus.ready) {
        urgent = t;
        break;
      }
    }
    urgent ??= upcomingTests.cast<Test?>().firstWhere(
      (t) => t?.status == TestStatus.live || t?.status == TestStatus.ready,
      orElse: () => null,
    );

    if (urgent == null) return const SizedBox.shrink();

    final cardBg = isDark ? const Color(0x33EF4444) : const Color(0xFFFEF2F2);
    final borderColor = isDark
        ? const Color(0x66EF4444)
        : const Color(0xFFFECACA);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LIVE ASSESSMENT IN PROGRESS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  urgent.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _pushThenRefresh('/tests/${urgent!.id}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(60, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Enter →',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Search (title / description). Kind filter + sort order live in the
  /// Filter sheet (AppBar's tune icon) only now — they used to also be
  /// repeated here as an always-visible chip row, the exact same controls
  /// in two places at once, which was most of what made this screen feel
  /// like "half the screen is buttons."
  Widget _filterBar(bool isDark) {
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('listing_search'),
          controller: _search,
          onChanged: _controller.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search tests',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: surfaceColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 1.5,
              ),
            ),
            suffixIcon: _controller.query.isEmpty
                ? null
                : IconButton(
                    key: const Key('listing_search_clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _search.clear();
                      _controller.setQuery('');
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(bool isDark) {
    final containerBg = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: isDark ? const Color(0xFF334155) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        labelColor: isDark ? Colors.white : const Color(0xFF2563EB),
        unselectedLabelColor: isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B),
        labelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          for (final c in TestListingScreen.tabs)
            Tab(text: TestListingScreen.tabLabel(c)),
        ],
      ),
    );
  }

  Widget _buildTab(ListingCategory category, bool isDark) {
    final isDrafts = category == ListingCategory.drafts;
    final error = isDrafts ? _controller.draftsError : _controller.error;

    if (!_controller.hasLoaded && _controller.isLoading) {
      return _buildSkeletonList(isDark);
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: tests.length,
              itemBuilder: (_, i) => _TestCard(
                key: ValueKey(tests[i].id),
                test: tests[i],
                isDark: isDark,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => JoinWithCodeSheet.show(context),
              icon: const Icon(Icons.vpn_key_outlined, size: 16),
              label: const Text('Join with code'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildSkeletonList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => _buildSkeletonCard(isDark),
    );
  }

  Widget _buildSkeletonCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final shimmerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9);

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 90,
                height: 16,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 60,
                height: 16,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: 200,
            height: 16,
            decoration: BoxDecoration(
              color: shimmerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 70,
                height: 14,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 90,
                height: 14,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
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

  Widget _noMatchState(ListingCategory category) {
    final hidden = _controller.unfilteredCount(category);
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 56,
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
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
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

  void _showFilterSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Filter & Sort',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Test Category',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        key: const Key('kind_chip_all'),
                        label: const Text('All'),
                        selected: _controller.kindFilter == null,
                        onSelected: (_) {
                          _controller.setKindFilter(null);
                          setSheetState(() {});
                        },
                      ),
                      for (final k in TestKind.filterable)
                        FilterChip(
                          key: Key('kind_chip_${k.name}'),
                          label: Text(k.label),
                          selected: _controller.kindFilter == k,
                          onSelected: (on) {
                            _controller.setKindFilter(on ? k : null);
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sort Order',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Newest'),
                        selected:
                            _controller.sortOrder == TestSortOrder.newestFirst,
                        onSelected: (_) {
                          _controller.setSortOrder(TestSortOrder.newestFirst);
                          setSheetState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Oldest'),
                        selected:
                            _controller.sortOrder == TestSortOrder.oldestFirst,
                        onSelected: (_) {
                          _controller.setSortOrder(TestSortOrder.oldestFirst);
                          setSheetState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Title A-Z'),
                        selected:
                            _controller.sortOrder == TestSortOrder.titleAZ,
                        onSelected: (_) {
                          _controller.setSortOrder(TestSortOrder.titleAZ);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          _search.clear();
                          _controller.clearFilters();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Reset All'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Tactile, modern academic Test Card.
class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.test,
    required this.onTap,
    this.isDark = false,
    super.key,
  });

  final Test test;
  final VoidCallback onTap;
  final bool isDark;

  TestProvenance _getTestProvenance(Test test) {
    if (test.groupId != null || test.testMode == 'group') {
      return TestProvenance.group;
    }
    final src =
        test.settings?['question_source']?.toString().toLowerCase() ?? '';
    final creationMethod =
        test.settings?['creation_method']?.toString().toLowerCase() ?? '';

    if (src.contains('book') ||
        src.contains('study') ||
        creationMethod.contains('study')) {
      return TestProvenance.myStudy;
    }
    if (src.contains('doc') ||
        src.contains('upload') ||
        creationMethod.contains('doc') ||
        creationMethod.contains('upload')) {
      return TestProvenance.document;
    }
    if (src.contains('ai') || creationMethod.contains('ai')) {
      return TestProvenance.ai;
    }
    return TestProvenance.standard;
  }

  @override
  Widget build(BuildContext context) {
    final kind = BackendMapping.fromBackend(test.testMode, test.settings);
    final statusColor = TestFormatters.statusColor(test.status);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final provenance = _getTestProvenance(test);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Badges Row
              Row(
                children: [
                  // Provenance Badge
                  if (provenance != TestProvenance.standard) ...[
                    _provenanceBadge(provenance, isDark),
                    const SizedBox(width: 6),
                  ],

                  // Test Kind Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      kind.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (test.status == TestStatus.live ||
                            test.status == TestStatus.ready) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          TestLifecycle.statusLabel(test.status),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Title
              Text(
                test.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  height: 1.3,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Description if available
              if (test.description != null &&
                  test.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  test.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 3. Metadata Chips Row
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (test.totalQuestions != null && test.totalQuestions! > 0)
                    _chip(
                      Icons.help_outline_rounded,
                      '${test.totalQuestions} Questions',
                      textSecondary,
                    ),
                  _chip(
                    Icons.timer_outlined,
                    TestFormatters.duration(test.durationSec),
                    textSecondary,
                  ),
                  if (test.startsAt != null)
                    _chip(
                      Icons.schedule_rounded,
                      TestFormatters.dateTime(test.startsAt),
                      textSecondary,
                    )
                  else if (test.createdAt != null)
                    _chip(
                      Icons.edit_calendar_outlined,
                      'Created ${TestFormatters.dateTime(test.createdAt)}',
                      textSecondary,
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // 4. Primary action — the whole card has always been tappable,
              // but nothing told the student that; an explicit button is
              // what actually gets tapped.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onTap,
                  icon: Icon(_actionIcon(test.status), size: 16),
                  label: Text(
                    _actionLabel(test.status),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _actionColor(test.status),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mirrors TestLifecycle's own status grouping — never invents a new
  /// status meaning, just picks the verb a student actually needs to see.
  static String _actionLabel(TestStatus status) => switch (status) {
    TestStatus.draft => 'Resume Editing',
    TestStatus.live || TestStatus.ready => 'Start Test',
    TestStatus.completed ||
    TestStatus.ended ||
    TestStatus.evaluated => 'View Results',
    TestStatus.cancelled || TestStatus.archived || TestStatus.expired =>
      'View Details',
    TestStatus.scheduled || TestStatus.published || TestStatus.unknown =>
      'View Details',
  };

  static IconData _actionIcon(TestStatus status) => switch (status) {
    TestStatus.draft => Icons.edit_outlined,
    TestStatus.live || TestStatus.ready => Icons.play_arrow_rounded,
    TestStatus.completed ||
    TestStatus.ended ||
    TestStatus.evaluated => Icons.bar_chart_rounded,
    _ => Icons.chevron_right_rounded,
  };

  static Color _actionColor(TestStatus status) => switch (status) {
    TestStatus.live || TestStatus.ready => const Color(0xFFEF4444),
    TestStatus.completed ||
    TestStatus.ended ||
    TestStatus.evaluated => const Color(0xFF059669),
    _ => const Color(0xFF2563EB),
  };

  Widget _provenanceBadge(TestProvenance provenance, bool isDark) {
    final (label, icon, color) = switch (provenance) {
      TestProvenance.myStudy => (
        'MY STUDY',
        Icons.menu_book_rounded,
        const Color(0xFF6366F1),
      ),
      TestProvenance.document => (
        'DOCUMENT',
        Icons.description_rounded,
        const Color(0xFF0891B2),
      ),
      TestProvenance.ai => (
        'AI GENERATED',
        Icons.auto_awesome_rounded,
        const Color(0xFF9333EA),
      ),
      TestProvenance.group => (
        'GROUP TEST',
        Icons.groups_rounded,
        const Color(0xFFD97706),
      ),
      TestProvenance.standard => (
        'TEST',
        Icons.assignment_rounded,
        Colors.grey,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
