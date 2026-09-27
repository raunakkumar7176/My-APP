import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common/test_card.dart';

/// Screen 1: Test Discovery Dashboard
/// Displays Goal Banner, metrics strip, Segmented Tabs (Live, Upcoming, Completed),
/// and a Floating Action Button for Custom Test Builder.
class TestsDashboardScreen extends StatefulWidget {
  const TestsDashboardScreen({super.key});

  @override
  State<TestsDashboardScreen> createState() => _TestsDashboardScreenState();
}

class _TestsDashboardScreenState extends State<TestsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final String _targetExam = 'UPSC CSE 2026';
  String _selectedSubjectFilter = 'All';

  // Sample data feeds for the 3 tabs
  late List<TestCardData> _liveTests;
  late List<TestCardData> _upcomingTests;
  late List<TestCardData> _completedTests;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _initializeSampleData();
  }

  void _initializeSampleData() {
    _liveTests = [
      const TestCardData(
        id: 'test_live_01',
        title: 'Modern Indian History: Freedom Struggle & Gandhian Era',
        subject: 'History',
        difficulty: TestCardDifficulty.medium,
        mode: 'Exam Simulation',
        questionCount: 25,
        totalMarks: 50.0,
        durationMinutes: 35,
        status: TestCardStatus.live,
      ),
      const TestCardData(
        id: 'test_live_02',
        title: 'Indian Polity: Fundamental Rights, DPSPs & Amendments',
        subject: 'Polity',
        difficulty: TestCardDifficulty.hard,
        mode: 'Speed Drill',
        questionCount: 20,
        totalMarks: 40.0,
        durationMinutes: 25,
        status: TestCardStatus.live,
      ),
      const TestCardData(
        id: 'test_live_03',
        title: 'General Science & Tech: Space Missions & Biotechnology',
        subject: 'Science',
        difficulty: TestCardDifficulty.easy,
        mode: 'Practice Mode',
        questionCount: 15,
        totalMarks: 30.0,
        durationMinutes: 20,
        status: TestCardStatus.live,
      ),
    ];

    _upcomingTests = [
      const TestCardData(
        id: 'test_upc_01',
        title: 'Physical Geography: Geomorphology & Oceanography Super Drill',
        subject: 'Geography',
        difficulty: TestCardDifficulty.hard,
        mode: 'Cohort Exam',
        questionCount: 50,
        totalMarks: 100.0,
        durationMinutes: 60,
        status: TestCardStatus.upcoming,
        scheduledDate: 'Tomorrow at 10:00 AM',
      ),
      const TestCardData(
        id: 'test_upc_02',
        title: 'Economic Development: Fiscal Policy & Banking Reforms',
        subject: 'Economy',
        difficulty: TestCardDifficulty.medium,
        mode: 'Weekly Revision',
        questionCount: 30,
        totalMarks: 60.0,
        durationMinutes: 45,
        status: TestCardStatus.upcoming,
        scheduledDate: '28 Sep 2026, 04:00 PM',
      ),
    ];

    _completedTests = [
      const TestCardData(
        id: 'test_comp_01',
        title: 'Ancient & Medieval History: Indus Valley to Mughal Decline',
        subject: 'History',
        difficulty: TestCardDifficulty.medium,
        mode: 'Exam Simulation',
        questionCount: 25,
        totalMarks: 50.0,
        durationMinutes: 35,
        status: TestCardStatus.completed,
        scoreObtained: 42.0,
        accuracyPercentage: 84.0,
        rank: 3,
        totalParticipants: 45,
      ),
      const TestCardData(
        id: 'test_comp_02',
        title: 'Environment & Ecology: Biodiversity Hotspots & Treaties',
        subject: 'Environment',
        difficulty: TestCardDifficulty.easy,
        mode: 'Practice Mode',
        questionCount: 20,
        totalMarks: 40.0,
        durationMinutes: 25,
        status: TestCardStatus.completed,
        scoreObtained: 34.0,
        accuracyPercentage: 85.0,
        rank: 7,
        totalParticipants: 62,
      ),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onStartTest(TestCardData test) {
    context.push('/tests/${test.id}/instructions', extra: test);
  }

  void _onViewResult(TestCardData test) {
    context.push('/tests/${test.id}/result', extra: test);
  }

  void _onViewLeaderboard(TestCardData test) {
    context.push('/tests/${test.id}/leaderboard', extra: test);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Examination & Test Hub',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Filter & Preferences',
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('custom_test_builder_fab'),
        onPressed: () {
          context.push('/tests/builder');
        },
        icon: const Icon(Icons.add_task_rounded),
        label: const Text(
          '+ Custom Test Builder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Goal Banner & Metrics Strip
                  _buildGoalBanner(theme, isDark),
                  const SizedBox(height: 14),
                  _buildMetricsStrip(theme, isDark),
                  const SizedBox(height: 18),

                  // Search & Subject Filter Chips
                  _buildFilterBar(isDark),
                  const SizedBox(height: 16),

                  // 2. Segmented Tabs
                  _buildSegmentedTabs(theme, isDark),
                  const SizedBox(height: 14),

                  // 3. Tab Content View
                  _buildActiveTabContent(),
                  const SizedBox(height: 80), // Fab spacing
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoalBanner(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A8A), const Color(0xFF1E293B)]
              : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF3B82F6) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Text('🎯', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Examination Target',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF1D4ED8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _targetExam,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Switch stream action
            },
            child: const Text(
              'Switch',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsStrip(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _metricTile(
            label: 'Tests Taken',
            value: '42',
            icon: Icons.quiz_outlined,
            color: const Color(0xFF2563EB),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            label: 'Avg Accuracy',
            value: '78.4%',
            icon: Icons.insights_rounded,
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            label: 'Points Earned',
            value: '1,250',
            icon: Icons.stars_rounded,
            color: const Color(0xFFD97706),
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    final subjects = [
      'All',
      'History',
      'Polity',
      'Geography',
      'Science',
      'Economy',
    ];

    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search mock tests, subjects or topics...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1E293B)
                : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          onChanged: (val) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: subjects.map((sub) {
              final isChosen = _selectedSubjectFilter == sub;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(sub),
                  selected: isChosen,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedSubjectFilter = sub);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedTabs(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tabs: [
          Tab(text: 'Live & Active (${_liveTests.length})'),
          Tab(text: 'Upcoming (${_upcomingTests.length})'),
          Tab(text: 'Completed (${_completedTests.length})'),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_tabController.index) {
      case 0:
        return _buildTestList(_liveTests);
      case 1:
        return _buildTestList(_upcomingTests);
      case 2:
        return _buildTestList(_completedTests);
      default:
        return _buildTestList(_liveTests);
    }
  }

  Widget _buildTestList(List<TestCardData> sourceList) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = sourceList.where((test) {
      final matchesQuery =
          query.isEmpty ||
          test.title.toLowerCase().contains(query) ||
          test.subject.toLowerCase().contains(query);
      final matchesSubject =
          _selectedSubjectFilter == 'All' ||
          test.subject.toLowerCase() == _selectedSubjectFilter.toLowerCase();
      return matchesQuery && matchesSubject;
    }).toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inbox_outlined,
                size: 48,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 12),
              const Text(
                'No tests found matching your criteria',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _selectedSubjectFilter = 'All';
                  });
                },
                child: const Text('Reset Filters'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return TestCard(
          key: Key('test_card_${item.id}'),
          data: item,
          onTap: () {
            if (item.status == TestCardStatus.live) {
              _onStartTest(item);
            } else if (item.status == TestCardStatus.completed) {
              _onViewResult(item);
            } else {
              _onStartTest(item);
            }
          },
          onAction: () {
            if (item.status == TestCardStatus.live) {
              _onStartTest(item);
            } else if (item.status == TestCardStatus.completed) {
              _onViewResult(item);
            } else {
              _onStartTest(item);
            }
          },
          onSecondaryAction: () {
            if (item.status == TestCardStatus.completed) {
              _onViewLeaderboard(item);
            }
          },
        );
      },
    );
  }
}
