import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/keep_alive_tab.dart';
import '../../data/study_repository.dart';
import '../../domain/study_chapter.dart';
import '../../domain/study_question.dart';
import '../../domain/study_topic.dart';
import '../controllers/chapter_hub_controller.dart';

/// Modernized Chapter Learning Hub: A focused, digital textbook command center
/// bridging structured reading, active recall practice, and timed exam testing.
class ChapterHubScreen extends StatefulWidget {
  const ChapterHubScreen({
    super.key,
    required this.chapterId,
    this.initialTab = 0,
    this.repository,
    this.controller,
    this.userId,
  });

  final String chapterId;
  final int initialTab;

  /// Optional repository injection for deterministic testing.
  final StudyRepository? repository;

  /// Optional controller injection for deterministic testing.
  final ChapterHubController? controller;

  /// Optional user ID injection for deterministic testing.
  final String? userId;

  @override
  State<ChapterHubScreen> createState() => _ChapterHubScreenState();
}

class _ChapterHubScreenState extends State<ChapterHubScreen>
    with SingleTickerProviderStateMixin {
  late final ChapterHubController _controller;
  late final TabController _tabController;
  late final bool _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null;
    _controller =
        widget.controller ??
        ChapterHubController(
          chapterId: widget.chapterId,
          repository: widget.repository,
          userId: widget.userId,
        );

    final initialTab = widget.initialTab.clamp(0, ChapterHubTab.values.length - 1);

    if (_internalController) {
      _controller.load();
      _controller.setActiveTab(initialTab);
    }

    _controller.addListener(_onControllerUpdate);

    _tabController = TabController(
      length: ChapterHubTab.values.length,
      vsync: this,
      initialIndex: initialTab,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _controller.setActiveTab(_tabController.index);
      }
    });
  }

  void _onControllerUpdate() {
    if (mounted) {
      if (_tabController.index != _controller.activeTabIndex) {
        _tabController.animateTo(_controller.activeTabIndex);
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    if (_internalController) {
      _controller.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isHindi = _controller.languageCode == 'hi';
    final chapter = _controller.chapter;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(context, isDark, isHindi, chapter),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: _buildBody(context, isDark, isHindi),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isDark,
    bool isHindi,
    StudyChapter? chapter,
  ) {
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final chapterTitle = chapter?.title ?? (isHindi ? 'अध्याय' : 'Chapter');

    // Breadcrumb text (e.g., "Part 1 • Chapter 03")
    final orderStr = chapter != null
        ? chapter.orderIndex.toString().padLeft(2, '0')
        : '';
    final breadcrumb =
        chapter?.partTitle != null && chapter!.partTitle!.trim().isNotEmpty
        ? '${chapter.partTitle} • ${isHindi ? "अध्याय $orderStr" : "Chapter $orderStr"}'
        : (isHindi ? 'अध्याय $orderStr' : 'Chapter $orderStr');

    return AppBar(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (orderStr.isNotEmpty) ...[
            Text(
              breadcrumb,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
          Text(
            chapterTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final next = _controller.languageCode == 'en' ? 'hi' : 'en';
                _controller.setLanguage(next);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.translate_rounded,
                      size: 14,
                      color: isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isHindi ? 'HI' : 'EN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool isDark, bool isHindi) {
    if (_controller.isLoadingChapter && _controller.chapter == null) {
      return _buildSkeletonHub(isDark);
    }

    if (_controller.errorMessage != null && _controller.chapter == null) {
      return Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x26EF4444)
                        : const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 28,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _controller.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 16),
                AppButton.primary(
                  label: isHindi ? 'पुनः प्रयास करें' : 'Retry',
                  onPressed: () => _controller.load(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // 1. Progress Hero Card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildChapterProgressCard(isDark, isHindi),
        ),
        const SizedBox(height: 12),

        // 2. Modern Segmented Tab Switcher
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildSegmentedTabBar(isDark, isHindi),
        ),
        const SizedBox(height: 8),

        // 3. Tab Contents
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              KeepAliveTab(child: _buildLearnTab(isDark, isHindi)),
              KeepAliveTab(child: _buildReadMcqTab(isDark, isHindi)),
              KeepAliveTab(child: _buildChapterPracticeTab(isDark, isHindi)),
            ],
          ),
        ),
      ],
    );
  }

  // ── 1. Compact Chapter Progress Card ──────────────────────────────────────
  Widget _buildChapterProgressCard(bool isDark, bool isHindi) {
    final totalTopics = _controller.totalTopicCount;
    final completedTopics = _controller.completedTopicCount;

    final progress = totalTopics > 0
        ? ((completedTopics / totalTopics) * 100.0).clamp(0.0, 100.0)
        : (_controller.chapter?.progressPercentage ?? 0.0);

    final totalMinutes = _controller.totalEstimatedMinutes;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final isAllCompleted = _controller.isAllCompleted;
    final progressColor = isAllCompleted
        ? const Color(0xFF10B981)
        : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB));

    // Smart Action Target
    final StudyTopic? nextTopic = _controller.nextTopicToLearn;

    final String actionLabel;
    if (isAllCompleted) {
      actionLabel = isHindi ? 'अध्याय दोहराएं ↺' : 'Review Chapter ↺';
    } else if (progress > 0) {
      actionLabel = isHindi ? 'अध्ययन जारी रखें →' : 'Continue Learning →';
    } else {
      actionLabel = isHindi ? 'अध्ययन शुरू करें →' : 'Start Learning →';
    }

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHindi ? 'अध्याय प्रगति समीक्षा' : 'Chapter Mastery',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isHindi
                          ? '${progress.toStringAsFixed(0)}% पूर्ण'
                          : '${progress.toStringAsFixed(0)}% Completed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (nextTopic != null) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await context.push(
                      '/study/topic/${nextTopic.id}?chapterId=${widget.chapterId}',
                    );
                    if (mounted) {
                      _controller.load();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // 8px Rounded Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (progress / 100.0).clamp(0.0, 1.0),
              backgroundColor: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),

          // Metrics Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _metricChip(
                icon: Icons.menu_book_rounded,
                label: isHindi
                    ? '$completedTopics / $totalTopics पूर्ण टॉपिक्स'
                    : '$completedTopics of $totalTopics Topics completed',
                isDark: isDark,
              ),
              if (totalMinutes > 0)
                _metricChip(
                  icon: Icons.schedule_rounded,
                  label: isHindi
                      ? 'अनुमानित समय: $totalMinutes मिनट'
                      : 'Est. Time: $totalMinutes mins',
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricChip({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final chipBg = isDark
        ? const Color(0xFF334155).withValues(alpha: 0.5)
        : const Color(0xFFF1F5F9);
    final textColor = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Segmented Tab Switcher ─────────────────────────────────────────────
  Widget _buildSegmentedTabBar(bool isDark, bool isHindi) {
    final containerBg = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final activeBg = isDark ? const Color(0xFF334155) : Colors.white;
    final activeText = isDark ? Colors.white : const Color(0xFF2563EB);
    final inactiveText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final tabs = [
      (
        key: const Key('chapter_hub_tab_learn'),
        icon: Icons.menu_book_rounded,
        title: isHindi ? 'अध्ययन' : 'Learn',
      ),
      (
        key: const Key('chapter_hub_tab_read_mcq'),
        icon: Icons.fact_check_rounded,
        title: isHindi ? 'MCQ पढ़ें' : 'Read MCQ',
      ),
      (
        key: const Key('chapter_hub_tab_practice'),
        icon: Icons.quiz_rounded,
        title: isHindi ? 'अभ्यास' : 'Practice',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final isSelected = _controller.activeTabIndex == idx;
          final t = tabs[idx];

          return Expanded(
            child: GestureDetector(
              key: t.key,
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _tabController.animateTo(idx);
                _controller.setActiveTab(idx);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? activeBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected && !isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      t.icon,
                      size: 16,
                      color: isSelected ? activeText : inactiveText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? activeText : inactiveText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Tab 1: Learn (Digital Textbook & Topics Hub) ──────────────────────────
  Widget _buildLearnTab(bool isDark, bool isHindi) {
    final topics = _controller.topics;

    if (_controller.isLoadingTopics && topics.isEmpty) {
      return _buildSkeletonTopicList(isDark);
    }

    if (topics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  size: 28,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isHindi
                    ? 'कोई टॉपिक उपलब्ध नहीं है'
                    : 'No topics available for this chapter',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isHindi
                    ? 'इस अध्याय के लिए जल्द ही सामग्री जोड़ी जाएगी।'
                    : 'Content will be added for this chapter shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        // "What you'll learn" Overview Box
        _buildLearningOverview(topics, isDark, isHindi),
        const SizedBox(height: 14),

        // Section Title
        Text(
          isHindi ? 'अध्याय विषय सूची' : 'Curriculum Topics',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),

        // Topic Cards List
        ...topics.map(
          (topic) => _TopicCard(
            key: ValueKey(topic.id),
            topic: topic,
            isDark: isDark,
            isHindi: isHindi,
            onTap: () async {
              await context.push(
                '/study/topic/${topic.id}?chapterId=${widget.chapterId}',
              );
              if (mounted) {
                _controller.load();
              }
            },
            onPracticeTap: () async {
              await context.push(
                '/study/topic/${topic.id}/practice?chapterId=${widget.chapterId}',
                extra: {
                  'topicTitle': topic.title,
                  'chapterTitle': _controller.chapter?.title ?? '',
                  'chapterId': widget.chapterId,
                },
              );
              if (mounted) {
                _controller.load();
              }
            },
          ),
        ),
        const SizedBox(height: 14),

        // Chapter-Wide Practice Card
        _buildChapterWidePracticeCard(topics, isDark, isHindi),
        const SizedBox(height: 14),

        // Revision & Weak Areas Card
        _buildRevisionCard(isDark, isHindi),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildLearningOverview(
    List<StudyTopic> topics,
    bool isDark,
    bool isHindi,
  ) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_rounded,
                size: 16,
                color: isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Text(
                isHindi ? 'आप इस अध्याय में सीखेंगे:' : "What you'll master:",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...topics
              .take(3)
              .map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFF2563EB),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  // ── Chapter Practice Card ────────────────────────────────────────────────
  Widget _buildChapterWidePracticeCard(
    List<StudyTopic> topics,
    bool isDark,
    bool isHindi,
  ) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final questionCount = _controller.totalQuestionCount;

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
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x26F59E0B)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.quiz_rounded,
                    size: 20,
                    color: Color(0xFFD97706),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHindi ? 'अध्याय अभ्यास' : 'Chapter Practice',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHindi
                          ? 'इस अध्याय के सभी विषयों के प्रश्नों का मिश्रित अभ्यास करें।'
                          : 'Practice questions across all topics in this chapter.',
                      style: TextStyle(fontSize: 12.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isHindi
                      ? '$questionCount प्रश्न उपलब्ध'
                      : '$questionCount Questions Available',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _tabController.animateTo(ChapterHubTab.practice.index);
                  _controller.setTab(ChapterHubTab.practice);
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: Text(
                  isHindi ? 'अध्याय अभ्यास करें' : 'Practice Chapter',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF2563EB),
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
            ],
          ),
        ],
      ),
    );
  }

  // ── Revision & Weak Areas Card ────────────────────────────────────────────
  Widget _buildRevisionCard(bool isDark, bool isHindi) {
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
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(
                Icons.bookmark_added_rounded,
                size: 20,
                color: Color(0xFF10B981),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHindi ? 'पुनरावृत्ति एवं स्मरण' : 'Revision & Recall',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isHindi
                      ? 'समीक्षा के लिए कोई गलत प्रश्न नहीं है। मुख्य अवधारणाओं और सूत्रों को दोहराएं।'
                      : 'No incorrect questions to review. Review key formulas and concept notes.',
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    _tabController.animateTo(ChapterHubTab.readMcq.index);
                    _controller.setTab(ChapterHubTab.readMcq);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155).withValues(alpha: 0.5)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility_rounded,
                          size: 13,
                          color: isDark
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isHindi
                              ? 'प्रश्न-उत्तर अध्ययन खोलें'
                              : 'Review Q&A Flashcards',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Read MCQ (Revision Mode — read-only) ───────────────────────────
  Widget _buildReadMcqTab(bool isDark, bool isHindi) {
    final questions = _controller.questions;

    if (_controller.isLoadingQuestions && questions.isEmpty) {
      return _buildSkeletonQuestionsList(isDark);
    }

    if (questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fact_check_rounded,
                  size: 28,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isHindi
                    ? 'कोई अभ्यास प्रश्न उपलब्ध नहीं हैं'
                    : 'No practice questions available yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isHindi
                    ? 'इस अध्याय के लिए प्रश्न जल्द ही लोड किए जाएंगे।'
                    : 'Questions will be generated or mapped for this chapter.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              AppButton.secondary(
                label: isHindi ? 'प्रश्न लोड करें' : 'Load Questions',
                size: AppButtonSize.sm,
                onPressed: () => _controller.loadQuestions(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      itemCount: questions.length + 1 + (_controller.hasMoreQuestions ? 1 : 0),
      itemBuilder: (context, index) {
        // Item 0: Revision Mode Notice Banner
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: _buildRevisionNoticeBanner(
              questions.length,
              isDark,
              isHindi,
            ),
          );
        }

        final qIdx = index - 1;
        if (qIdx == questions.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: _controller.isLoadingMoreQuestions
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : AppButton.outlined(
                      label: isHindi
                          ? 'और प्रश्न लोड करें'
                          : 'Load More Questions',
                      size: AppButtonSize.sm,
                      onPressed: () => _controller.loadMoreQuestions(),
                    ),
            ),
          );
        }

        final q = questions[qIdx];
        return _QuestionStudyCard(
          key: ValueKey(q.id),
          question: q,
          number: qIdx + 1,
          isDark: isDark,
          isHindi: isHindi,
        );
      },
    );
  }

  Widget _buildRevisionNoticeBanner(int count, bool isDark, bool isHindi) {
    final bg = isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5);
    final border = isDark ? const Color(0x4D10B981) : const Color(0xFFA7F3D0);
    final text = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_rounded, size: 18, color: text),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHindi
                      ? 'स्मरण एवं त्वरित पुनरावृत्ति मोड सक्रिय ($count प्रश्न)'
                      : 'Active Recall & Revision Mode ($count Questions)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isHindi
                      ? 'सही विकल्प और विस्तृत समाधान तुरंत याद रखने के लिए पहले से दर्शित हैं। इंटरैक्टिव अभ्यास के लिए "अभ्यास" टैब खोलें।'
                      : 'Correct options and in-depth explanations are pre-highlighted for textbook memorization. Open the "Practice" tab for the interactive quiz.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: text.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Chapter Practice (interactive card-by-card quiz) ───────────────
  Widget _buildChapterPracticeTab(bool isDark, bool isHindi) {
    if (_controller.isLoadingQuestions && _controller.questions.isEmpty) {
      return _buildSkeletonQuestionsList(isDark);
    }

    if (_controller.questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.quiz_rounded,
                  size: 28,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isHindi
                    ? 'कोई अभ्यास प्रश्न उपलब्ध नहीं हैं'
                    : 'No practice questions available yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              AppButton.secondary(
                label: isHindi ? 'प्रश्न लोड करें' : 'Load Questions',
                size: AppButtonSize.sm,
                onPressed: () => _controller.loadQuestions(),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller.isPracticeComplete) {
      return _buildPracticeSummary(isDark, isHindi);
    }

    final question = _controller.currentPracticeQuestion;
    if (question == null) {
      return _buildPracticeSummary(isDark, isHindi);
    }

    return ListView(
      key: const Key('chapter_practice_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Progress strip
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _controller.questions.isEmpty
                      ? 0
                      : (_controller.practiceIndex /
                              _controller.questions.length)
                          .clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF2563EB),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_controller.practiceIndex + 1}/${_controller.questions.length}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _PracticeQuestionCard(
          key: ValueKey(question.id),
          question: question,
          isDark: isDark,
          isHindi: isHindi,
          controller: _controller,
        ),
        const SizedBox(height: 16),
        if (_controller.isAnswerChecked(question.id))
          AppButton.primary(
            key: const Key('practice_next_button'),
            label: _controller.hasNextPracticeQuestion
                ? (isHindi ? 'अगला प्रश्न →' : 'Next Question →')
                : (isHindi ? 'अभ्यास पूरा करें 🎉' : 'Finish Practice 🎉'),
            onPressed: () => _controller.nextPracticeQuestion(),
          ),
      ],
    );
  }

  Widget _buildPracticeSummary(bool isDark, bool isHindi) {
    final total = _controller.questions.length;
    var correct = 0;
    for (final q in _controller.questions) {
      if (_controller.getSelectedOption(q.id) == q.correctOption) correct++;
    }
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          key: const Key('chapter_practice_summary'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              isHindi ? 'अभ्यास पूर्ण हुआ!' : 'Practice Complete',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isHindi ? '$correct / $total सही उत्तर' : '$correct / $total Correct',
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
            const SizedBox(height: 20),
            AppButton.outlined(
              label: isHindi ? 'पुनः अभ्यास करें 🔁' : 'Practice Again 🔁',
              icon: Icons.replay_rounded,
              onPressed: () => _controller.restartPractice(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Skeletons ─────────────────────────────────────────────────────────────
  Widget _buildSkeletonHub(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        _buildSkeletonBox(height: 120, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 44, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 90, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 90, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 90, isDark: isDark),
      ],
    );
  }

  Widget _buildSkeletonTopicList(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        _buildSkeletonBox(height: 90, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 90, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 90, isDark: isDark),
      ],
    );
  }

  Widget _buildSkeletonQuestionsList(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        _buildSkeletonBox(height: 48, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 160, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonBox(height: 160, isDark: isDark),
      ],
    );
  }

  Widget _buildSkeletonBox({required double height, required bool isDark}) {
    final baseColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final shimmerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(shimmerColor),
          ),
        ),
      ),
    );
  }
}

/// Tactile interactive Topic Card with micro-interactions and duration badge.
class _TopicCard extends StatefulWidget {
  const _TopicCard({
    super.key,
    required this.topic,
    required this.isDark,
    required this.isHindi,
    required this.onTap,
    this.onPracticeTap,
  });

  final StudyTopic topic;
  final bool isDark;
  final bool isHindi;
  final VoidCallback onTap;
  final VoidCallback? onPracticeTap;

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final isDark = widget.isDark;
    final isHindi = widget.isHindi;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final indexFormatted = topic.orderIndex.toString().padLeft(2, '0');

    final statusBg = topic.isCompleted
        ? (isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5))
        : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9));

    final statusColor = topic.isCompleted
        ? const Color(0xFF10B981)
        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order Index Badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: topic.isCompleted
                          ? const Color(0x4D10B981)
                          : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: topic.isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: Color(0xFF10B981),
                          )
                        : Text(
                            indexFormatted,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),

                // Topic Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          height: 1.3,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (topic.summary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          topic.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Footer Row: Status Pill + Minutes
                      Row(
                        children: [
                          _topicStatusPill(topic.isCompleted, isDark, isHindi),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                        .withValues(alpha: 0.5)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 12,
                                  color: textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${topic.estimatedMinutes} ${isHindi ? "मिनट" : "mins"}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.onPracticeTap != null) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onPracticeTap,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                            .withValues(alpha: 0.6)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF475569)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.quiz_outlined,
                                      size: 11,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isHindi ? 'अभ्यास' : 'Practice',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? const Color(0xFFCBD5E1)
                                            : const Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topicStatusPill(bool isCompleted, bool isDark, bool isHindi) {
    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x4D10B981)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 12, color: Color(0xFF10B981)),
            const SizedBox(width: 3),
            Text(
              isHindi ? 'पूर्ण' : 'Done',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x263B82F6) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isHindi ? 'पढ़ें →' : 'Read →',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
        ),
      ),
    );
  }
}

/// Study Practice Question Card with interactive recall, highlighted correct option, and detailed explanation.
/// Read-only revision card for the Read MCQ tab: question, correct option
/// highlighted, and explanation — all shown immediately with no tap
/// interaction, per that tab's "fast revision without testing" purpose.
class _QuestionStudyCard extends StatelessWidget {
  const _QuestionStudyCard({
    super.key,
    required this.question,
    required this.number,
    required this.isDark,
    required this.isHindi,
  });

  final StudyQuestion question;
  final int number;
  final bool isDark;
  final bool isHindi;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Container(
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
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x263B82F6)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x4D3B82F6)
                          : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Text(
                    'Q$number',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    question.question,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      height: 1.4,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Options
            ...List.generate(question.options.length, (optIdx) {
              final optionText = question.options[optIdx];
              final isCorrect = optIdx == question.correctOption;

              final Color optBg;
              final Color optBorder;
              final Color optText;

              if (isCorrect) {
                optBg = isDark
                    ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                    : const Color(0xFFECFDF5);
                optBorder = const Color(0xFF10B981);
                optText = isDark
                    ? const Color(0xFF6EE7B7)
                    : const Color(0xFF065F46);
              } else {
                optBg = isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC);
                optBorder = isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0);
                optText = isDark ? Colors.white : const Color(0xFF1E293B);
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: optBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: optBorder,
                      width: isCorrect ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCorrect
                              ? const Color(0xFF10B981)
                              : Colors.transparent,
                          border: Border.all(
                            color: isCorrect
                                ? const Color(0xFF10B981)
                                : (isDark
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF94A3B8)),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: isCorrect
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : Text(
                                  String.fromCharCode(65 + optIdx),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: textSecondary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          optionText,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isCorrect
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: optText,
                          ),
                        ),
                      ),
                      if (isCorrect) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF047857)
                                : const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isHindi ? 'सही उत्तर' : 'Correct',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            // Explanation Callout (Open by Default)
            if (question.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFA7F3D0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_rounded,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isHindi
                              ? 'विस्तृत व्याख्या / समाधान:'
                              : 'Explanation & Concept Note:',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF6EE7B7)
                                : const Color(0xFF166534),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      question.explanation,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Interactive Chapter Practice card: one question at a time. Selecting an
/// option gives instant green/red feedback (haptic on tap) and reveals a
/// collapsible explanation; a bookmark icon saves the question locally
/// (no "Saved Questions" backend exists yet, so this mirrors the same
/// local-only bookmark pattern already used for topic bookmarks elsewhere
/// in Study — never a fabricated server write).
class _PracticeQuestionCard extends StatelessWidget {
  const _PracticeQuestionCard({
    super.key,
    required this.question,
    required this.isDark,
    required this.isHindi,
    required this.controller,
  });

  final StudyQuestion question;
  final bool isDark;
  final bool isHindi;
  final ChapterHubController controller;

  void _onSelect(BuildContext context, int optIdx) {
    if (controller.isAnswerChecked(question.id)) return;
    final isCorrect = optIdx == question.correctOption;
    HapticFeedback.mediumImpact();
    controller.selectOption(question.id, optIdx);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCorrect
              ? (isHindi ? '✓ सही उत्तर! +1 अंक' : '✓ Correct! +1 point')
              : (isHindi ? '✗ गलत उत्तर' : '✗ Incorrect'),
        ),
        backgroundColor: isCorrect
            ? const Color(0xFF10B981)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleBookmark(BuildContext context) {
    controller.toggleBookmark(question.id);
    final nowBookmarked = controller.isBookmarked(question.id);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowBookmarked
              ? (isHindi ? 'प्रश्न सेव किया गया' : 'Saved to bookmarks')
              : (isHindi ? 'बुकमार्क हटाया गया' : 'Bookmark removed'),
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final selectedOpt = controller.getSelectedOption(question.id);
    final isChecked = controller.isAnswerChecked(question.id);
    final isBookmarked = controller.isBookmarked(question.id);
    final explanationExpanded = controller.isExplanationExpanded(question.id);

    return Container(
      key: Key('practice_question_${question.id}'),
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
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  question.question,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    height: 1.4,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const Key('practice_bookmark_button'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _toggleBookmark(context),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    isBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 22,
                    color: isBookmarked
                        ? const Color(0xFF2563EB)
                        : textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ...List.generate(question.options.length, (optIdx) {
            final optionText = question.options[optIdx];
            final isCorrect = optIdx == question.correctOption;
            final isUserPick = selectedOpt == optIdx;

            final Color optBg;
            final Color optBorder;
            final Color optText;

            if (!isChecked) {
              optBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
              optBorder = isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0);
              optText = isDark ? Colors.white : const Color(0xFF1E293B);
            } else if (isCorrect) {
              optBg = isDark
                  ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                  : const Color(0xFFECFDF5);
              optBorder = const Color(0xFF10B981);
              optText = isDark
                  ? const Color(0xFF6EE7B7)
                  : const Color(0xFF065F46);
            } else if (isUserPick) {
              optBg = isDark
                  ? const Color(0xFF450A0A).withValues(alpha: 0.5)
                  : const Color(0xFFFEF2F2);
              optBorder = const Color(0xFFEF4444);
              optText = isDark
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFF991B1B);
            } else {
              optBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
              optBorder = isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0);
              optText = isDark ? Colors.white : const Color(0xFF1E293B);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: InkWell(
                key: Key('practice_option_${question.id}_$optIdx'),
                borderRadius: BorderRadius.circular(10),
                onTap: isChecked ? null : () => _onSelect(context, optIdx),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: optBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: optBorder,
                      width: (isChecked && (isCorrect || isUserPick)) ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isChecked && isCorrect
                              ? const Color(0xFF10B981)
                              : isChecked && isUserPick
                              ? const Color(0xFFEF4444)
                              : Colors.transparent,
                          border: Border.all(
                            color: isChecked && isCorrect
                                ? const Color(0xFF10B981)
                                : isChecked && isUserPick
                                ? const Color(0xFFEF4444)
                                : (isDark
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF94A3B8)),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: isChecked && isCorrect
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : isChecked && isUserPick
                              ? const Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : Text(
                                  String.fromCharCode(65 + optIdx),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: textSecondary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          optionText,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: (isChecked && (isCorrect || isUserPick))
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: optText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          if (isChecked && question.explanation.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              key: const Key('practice_toggle_explanation'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => controller.toggleExplanation(question.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      explanationExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isHindi ? 'व्याख्या देखें' : 'Show explanation',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (explanationExpanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFA7F3D0),
                  ),
                ),
                child: Text(
                  question.explanation,
                  key: const Key('practice_explanation_text'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF1E293B),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
