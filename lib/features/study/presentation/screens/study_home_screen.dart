import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/continue_learning.dart';
import '../../domain/study_subject.dart';
import '../controllers/study_home_controller.dart';

/// Primary Study Home Dashboard Screen.
class StudyHomeScreen extends StatefulWidget {
  const StudyHomeScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
  late final StudyHomeController _controller;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = StudyHomeController()..load();
    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildLanguagePill(bool isDark) {
    return InkWell(
      borderRadius: AppRadius.pillBorder,
      onTap: () => _controller.toggleLanguage(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.primaryContainerDark.withAlpha(120)
              : AppColors.primaryContainerLight,
          borderRadius: AppRadius.pillBorder,
          border: Border.all(
            color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.translate_rounded,
              size: 14,
              color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
            ),
            AppSpacing.hGapXs,
            Text(
              _controller.isHindi ? 'HI' : 'EN',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final content = RefreshIndicator(
      onRefresh: () => _controller.load(),
      child: _buildBody(context, isDark),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _controller.isHindi ? 'मेरा अध्ययन' : 'My Study',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10.0,
              horizontal: 4.0,
            ),
            child: _buildLanguagePill(isDark),
          ),
          IconButton(
            icon: Icon(
              _isSearchVisible ? Icons.close_rounded : Icons.search_rounded,
            ),
            tooltip: 'Search subjects',
            onPressed: () {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
                if (!_isSearchVisible) {
                  _searchController.clear();
                  _controller.setSearchQuery('');
                }
              });
            },
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (_controller.isLoading && _controller.subjects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.errorMessage != null && _controller.subjects.isEmpty) {
      return Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
              AppSpacing.vGapMd,
              Text(
                _controller.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              AppSpacing.vGapMd,
              AppButton.primary(
                label: 'Retry',
                onPressed: () => _controller.load(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        if (widget.embedded) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _controller.isHindi ? 'मेरा अध्ययन' : 'My Study',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _isSearchVisible
                          ? Icons.close_rounded
                          : Icons.search_rounded,
                      size: 22,
                    ),
                    tooltip: 'Search subjects',
                    onPressed: () {
                      setState(() {
                        _isSearchVisible = !_isSearchVisible;
                        if (!_isSearchVisible) {
                          _searchController.clear();
                          _controller.setSearchQuery('');
                        }
                      });
                    },
                  ),
                  _buildLanguagePill(isDark),
                ],
              ),
            ],
          ),
          AppSpacing.vGapSm,
        ],
        if (_isSearchVisible) ...[_buildSearchBar(isDark), AppSpacing.vGapMd],
        _buildContinueLearningSection(isDark),
        AppSpacing.vGapLg,
        _buildProgressSummaryRow(isDark),
        AppSpacing.vGapLg,
        _buildSubjectsSection(isDark),
        AppSpacing.vGapXl,
      ],
    );
  }

  // ── Search Bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      onChanged: _controller.setSearchQuery,
      decoration: InputDecoration(
        hintText: _controller.isHindi
            ? 'विषय या अध्याय खोजें...'
            : 'Search subjects or chapters...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  _controller.setSearchQuery('');
                },
              )
            : null,
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ── Section 1: Continue Learning ───────────────────────────────────────────
  Widget _buildContinueLearningSection(bool isDark) {
    final snapshot = _controller.continueLearning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.bolt_rounded,
              size: 20,
              color: AppColors.primaryLight,
            ),
            AppSpacing.hGapXs,
            Text(
              _controller.isHindi ? 'अध्ययन जारी रखें' : 'Continue Learning',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        AppSpacing.vGapSm,
        if (snapshot != null)
          _buildContinueLearningCard(snapshot, isDark)
        else
          _buildEmptyContinueLearningCard(isDark),
      ],
    );
  }

  Widget _buildContinueLearningCard(
    ContinueLearningSnapshot snapshot,
    bool isDark,
  ) {
    return AppCard(
      variant: AppCardVariant.elevated,
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.primaryContainerDark
                      : AppColors.primaryContainerLight,
                  borderRadius: AppRadius.smBorder,
                ),
                child: Text(
                  '${snapshot.subjectName} • ${snapshot.chapterTitle}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.primaryDark
                        : AppColors.primaryLight,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          Text(
            snapshot.topicTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          AppSpacing.vGapMd,
          LinearProgressIndicator(
            value: (snapshot.progressPercentage / 100.0).clamp(0.05, 1.0),
            backgroundColor: isDark
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
            borderRadius: AppRadius.pillBorder,
            minHeight: 6,
          ),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton.primary(
                label: _controller.isHindi ? 'जारी रखें →' : 'Continue →',
                size: AppButtonSize.sm,
                onPressed: () {
                  context.push(
                    '/study/topic/${snapshot.topicId}?chapterId=${snapshot.chapterId}',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContinueLearningCard(bool isDark) {
    return AppCard(
      variant: AppCardVariant.filled,
      backgroundColor: isDark
          ? const Color(0xFF1E293B)
          : const Color(0xFFF8FAFC),
      padding: AppSpacing.cardPadding,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primaryContainerDark.withAlpha(80)
                  : AppColors.primaryContainerLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: AppColors.primaryLight,
              size: 24,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _controller.isHindi
                      ? 'नया अध्याय शुरू करें'
                      : 'Start Learning',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.vGapXs,
                Text(
                  _controller.isHindi
                      ? 'नीचे दिए गए किसी भी विषय को चुनें और पढ़ना शुरू करें।'
                      : 'Pick any subject below to begin your comprehensive preparation.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2: Study Progress Summary ──────────────────────────────────────
  Widget _buildProgressSummaryRow(bool isDark) {
    final summary = _controller.progressSummary;

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            count: '${_controller.subjects.length}',
            label: _controller.isHindi ? 'कुल विषय' : 'Subjects',
            icon: Icons.layers_rounded,
            color: AppColors.primaryLight,
          ),
          Container(
            width: 1,
            height: 36,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          _buildSummaryItem(
            count: '${summary.completedChaptersCount}',
            label: _controller.isHindi ? 'अध्याय पूर्ण' : 'Chapters Done',
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
          ),
          Container(
            width: 1,
            height: 36,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          _buildSummaryItem(
            count: '${summary.completedTopicsCount}',
            label: _controller.isHindi ? 'टॉपिक्स पूर्ण' : 'Topics Done',
            icon: Icons.task_alt_rounded,
            color: AppColors.secondaryLight,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String count,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            AppSpacing.hGapXs,
            Text(
              count,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  // ── Section 3: Subjects List ───────────────────────────────────────────────
  Widget _buildSubjectsSection(bool isDark) {
    final subjects = _controller.subjects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.school_rounded,
              size: 20,
              color: AppColors.secondaryLight,
            ),
            AppSpacing.hGapXs,
            Text(
              _controller.isHindi ? 'सभी विषय' : 'Subjects',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        AppSpacing.vGapSm,
        if (subjects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                _controller.isHindi
                    ? 'कोई विषय नहीं मिला।'
                    : 'No subjects found matching your query.',
                style: const TextStyle(color: AppColors.textSecondaryLight),
              ),
            ),
          )
        else
          ...subjects.map(
            (subject) => _buildSubjectCard(subject, isDark,
                key: ValueKey(subject.id)),
          ),
      ],
    );
  }

  Widget _buildSubjectCard(StudySubject subject, bool isDark, {Key? key}) {
    final iconData = _resolveIcon(subject.icon);

    return AppCard(
      key: key,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      variant: AppCardVariant.outlined,
      onTap: () {
        context.push('/study/subject/${subject.id}');
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primaryContainerDark.withAlpha(90)
                  : AppColors.primaryContainerLight,
              borderRadius: AppRadius.mdBorder,
            ),
            child: Icon(
              iconData,
              size: 28,
              color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        subject.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                        borderRadius: AppRadius.pillBorder,
                      ),
                      child: Text(
                        '${subject.chapterCount} ${_controller.isHindi ? "अध्याय" : "Chapters"}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subject.description.isNotEmpty) ...[
                  AppSpacing.vGapXs,
                  Text(
                    subject.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
                AppSpacing.vGapSm,
                LinearProgressIndicator(
                  value: (subject.progressPercentage / 100.0).clamp(0.0, 1.0),
                  backgroundColor: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  borderRadius: AppRadius.pillBorder,
                  minHeight: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryLight,
          ),
        ],
      ),
    );
  }

  IconData _resolveIcon(String? iconKey) {
    return switch (iconKey) {
      'calculate' || 'mathematics' => Icons.calculate_rounded,
      'science' => Icons.science_rounded,
      'history' || 'history_edu' => Icons.history_edu_rounded,
      'translate' || 'english' => Icons.translate_rounded,
      'language' || 'hindi' => Icons.language_rounded,
      'public' || 'geography' => Icons.public_rounded,
      'psychology' || 'reasoning' => Icons.psychology_rounded,
      'newspaper' || 'current_affairs' || 'feed' => Icons.newspaper_rounded,
      'account_balance' || 'polity' || 'gavel' => Icons.account_balance_rounded,
      'trending_up' || 'economics' => Icons.trending_up_rounded,
      'eco' || 'environment' => Icons.eco_rounded,
      _ => Icons.menu_book_rounded,
    };
  }
}
