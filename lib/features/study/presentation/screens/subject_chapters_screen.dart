import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/study_repository.dart';
import '../../domain/study_chapter.dart';
import '../../domain/study_subject.dart';

enum ChapterFilter { all, notStarted, inProgress, completed }

/// Modernized Subject Chapters Screen: A focused, high-precision academic
/// syllabus and chapter navigation center.
class SubjectChaptersScreen extends StatefulWidget {
  const SubjectChaptersScreen({
    super.key,
    required this.subjectId,
    this.repository,
    this.userId,
  });

  final String subjectId;

  /// Optional repository injection for deterministic testing.
  final StudyRepository? repository;

  /// Optional user ID injection for deterministic testing.
  final String? userId;

  @override
  State<SubjectChaptersScreen> createState() => _SubjectChaptersScreenState();
}

class _SubjectChaptersScreenState extends State<SubjectChaptersScreen> {
  late final StudyRepository _repository =
      widget.repository ?? const SupabaseStudyRepository();

  String _languageCode = 'en';
  bool _isLoading = true;
  String? _errorMessage;

  StudySubject? _subject;
  List<StudyChapter> _allChapters = [];
  ChapterFilter _selectedFilter = ChapterFilter.all;
  String? _selectedPartKey;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool get _hasParts => _allChapters.any(
    (c) => c.partKey != null && c.partKey!.trim().isNotEmpty,
  );

  List<({String key, String title, int orderIndex, int count})>
  get _availableParts {
    final Map<String, ({String key, String title, int orderIndex, int count})>
    partsMap = {};
    for (final c in _allChapters) {
      if (c.partKey != null && c.partKey!.trim().isNotEmpty) {
        final key = c.partKey!;
        final title = c.partTitle ?? key.replaceAll('_', ' ');
        if (!partsMap.containsKey(key)) {
          partsMap[key] = (
            key: key,
            title: title,
            orderIndex: c.partOrderIndex,
            count: 1,
          );
        } else {
          final existing = partsMap[key]!;
          partsMap[key] = (
            key: key,
            title: existing.title,
            orderIndex: existing.orderIndex,
            count: existing.count + 1,
          );
        }
      }
    }
    final list = partsMap.values.toList();
    list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? userId = widget.userId;
      if (userId == null) {
        try {
          userId = AuthService.currentUser?.id;
        } catch (_) {
          userId = null;
        }
      }

      // 1. Fetch subjects to get current subject details
      final subjects = await _repository.fetchSubjects(
        languageCode: _languageCode,
      );
      final found = subjects.where((s) => s.id == widget.subjectId);
      if (found.isNotEmpty) {
        _subject = found.first;
      }

      // 2. Fetch chapters for subject
      _allChapters = await _repository.fetchChapters(
        subjectId: widget.subjectId,
        languageCode: _languageCode,
        userId: userId,
      );
    } catch (e, st) {
      AppLogger.error('SubjectChaptersScreen._load error: $e\n$st');
      _errorMessage = 'Failed to load chapters for this subject.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleLanguage() {
    final next = _languageCode == 'en' ? 'hi' : 'en';
    setState(() {
      _languageCode = next;
    });
    _load();
  }

  List<StudyChapter> get _filteredChapters {
    return _allChapters.where((c) {
      // 0. Part filter condition
      if (_selectedPartKey != null && c.partKey != _selectedPartKey) {
        return false;
      }

      // 1. Filter chip condition
      final matchesFilter = switch (_selectedFilter) {
        ChapterFilter.all => true,
        ChapterFilter.notStarted => c.progressPercentage <= 0,
        ChapterFilter.inProgress =>
          c.progressPercentage > 0 && c.progressPercentage < 100,
        ChapterFilter.completed => c.progressPercentage >= 100,
      };
      if (!matchesFilter) return false;

      // 2. Search query condition
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return c.title.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q) ||
            (c.partTitle?.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  double get _overallProgress {
    if (_allChapters.isEmpty) return 0.0;
    final total = _allChapters.fold<double>(
      0.0,
      (acc, c) => acc + c.progressPercentage,
    );
    return (total / _allChapters.length).clamp(0.0, 100.0);
  }

  int get _completedCount =>
      _allChapters.where((c) => c.progressPercentage >= 100).length;

  int get _inProgressCount => _allChapters
      .where((c) => c.progressPercentage > 0 && c.progressPercentage < 100)
      .length;

  int get _notStartedCount =>
      _allChapters.where((c) => c.progressPercentage <= 0).length;

  int get _totalTopicsCount =>
      _allChapters.fold<int>(0, (acc, c) => acc + c.topicCount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isHindi = _languageCode == 'hi';

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(context, isDark, isHindi),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
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
  ) {
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final subjectTitle = _subject?.name ?? (isHindi ? 'अध्याय' : 'Chapters');

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
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? const Color(0x263B82F6) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? const Color(0x4D3B82F6)
                    : const Color(0xFFBFDBFE),
              ),
            ),
            child: Center(
              child: Icon(
                _resolveIcon(_subject?.icon),
                size: 20,
                color: isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              subjectTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
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
              onTap: _toggleLanguage,
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
    if (_isLoading && _allChapters.isEmpty) {
      return _buildSkeletonList(isDark);
    }

    if (_errorMessage != null && _allChapters.isEmpty) {
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
                  _errorMessage!,
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
                  onPressed: _load,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filtered = _filteredChapters;

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF2563EB),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // 1. Subject Hero & Progress Overview
          _buildProgressHeroCard(isDark, isHindi),
          const SizedBox(height: 16),

          // 2. Search Input
          _buildSearchBar(isDark, isHindi),
          const SizedBox(height: 12),

          // 3. Section / Part Filter Chips (if multi-part)
          if (_hasParts) ...[
            _buildPartChips(isDark, isHindi),
            const SizedBox(height: 12),
          ],

          // 4. Status Filter Chips
          _buildFilterChips(isDark, isHindi),
          const SizedBox(height: 16),

          // 5. Chapter List or Empty View
          _buildChapterList(filtered, isDark, isHindi),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildProgressHeroCard(bool isDark, bool isHindi) {
    final progress = _overallProgress;
    final totalChapters = _allChapters.length;
    final completed = _completedCount;
    final totalTopics = _totalTopicsCount;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final isAllCompleted = totalChapters > 0 && completed == totalChapters;
    final progressColor = isAllCompleted
        ? const Color(0xFF10B981)
        : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
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
                      isHindi ? 'विषय प्रगति समीक्षा' : 'Syllabus Mastery',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        textBaseline: TextBaseline.alphabetic,
                        letterSpacing: 0.5,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isHindi
                          ? '${progress.toStringAsFixed(0)}% पाठ्यक्रम पूर्ण'
                          : '${progress.toStringAsFixed(0)}% Completed',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isAllCompleted
                      ? (isDark
                            ? const Color(0x2610B981)
                            : const Color(0xFFECFDF5))
                      : (isDark
                            ? const Color(0x263B82F6)
                            : const Color(0xFFEFF6FF)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isAllCompleted
                        ? const Color(0x4D10B981)
                        : (isDark
                              ? const Color(0x4D3B82F6)
                              : const Color(0xFFBFDBFE)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAllCompleted
                          ? Icons.check_circle_rounded
                          : Icons.auto_graph_rounded,
                      size: 15,
                      color: progressColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isAllCompleted
                          ? (isHindi ? 'निपुण' : 'Mastered')
                          : (isHindi ? 'प्रगतिशील' : 'In Progress'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: progressColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress Track
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
          const SizedBox(height: 14),

          // Metadata Chips Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip(
                icon: Icons.menu_book_rounded,
                label: isHindi
                    ? '$completed / $totalChapters अध्याय'
                    : '$completed of $totalChapters Chapters',
                isDark: isDark,
              ),
              if (totalTopics > 0)
                _metricChip(
                  icon: Icons.topic_rounded,
                  label: isHindi
                      ? '$totalTopics टॉपिक्स'
                      : '$totalTopics Topics',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, bool isHindi) {
    final fieldBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val.trim();
          });
        },
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: isHindi ? 'अध्याय खोजें...' : 'Search chapters...',
          hintStyle: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPartChips(bool isDark, bool isHindi) {
    final parts = _availableParts;
    if (parts.isEmpty) return const SizedBox.shrink();

    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isHindi ? 'खंड / भाग' : 'Sections / Parts',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildChoicePill(
                label: isHindi ? 'सभी भाग' : 'All Sections',
                isSelected: _selectedPartKey == null,
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _selectedPartKey = null;
                  });
                },
              ),
              ...parts.map((p) {
                final isSelected = _selectedPartKey == p.key;
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: _buildChoicePill(
                    label: '${p.title} (${p.count})',
                    isSelected: isSelected,
                    isDark: isDark,
                    onTap: () {
                      setState(() {
                        _selectedPartKey = isSelected ? null : p.key;
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(bool isDark, bool isHindi) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildChoicePill(
            label: isHindi
                ? 'सभी (${_allChapters.length})'
                : 'All (${_allChapters.length})',
            isSelected: _selectedFilter == ChapterFilter.all,
            isDark: isDark,
            onTap: () {
              setState(() {
                _selectedFilter = ChapterFilter.all;
              });
            },
          ),
          const SizedBox(width: 8),
          _buildChoicePill(
            label: isHindi
                ? 'शुरू नहीं हुआ ($_notStartedCount)'
                : 'Not Started ($_notStartedCount)',
            isSelected: _selectedFilter == ChapterFilter.notStarted,
            isDark: isDark,
            onTap: () {
              setState(() {
                _selectedFilter = ChapterFilter.notStarted;
              });
            },
          ),
          const SizedBox(width: 8),
          _buildChoicePill(
            label: isHindi
                ? 'प्रगति पर ($_inProgressCount)'
                : 'In Progress ($_inProgressCount)',
            isSelected: _selectedFilter == ChapterFilter.inProgress,
            isDark: isDark,
            onTap: () {
              setState(() {
                _selectedFilter = ChapterFilter.inProgress;
              });
            },
          ),
          const SizedBox(width: 8),
          _buildChoicePill(
            label: isHindi
                ? 'पूर्ण ($_completedCount)'
                : 'Completed ($_completedCount)',
            isSelected: _selectedFilter == ChapterFilter.completed,
            isDark: isDark,
            onTap: () {
              setState(() {
                _selectedFilter = ChapterFilter.completed;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChoicePill({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final activeBg = isDark ? const Color(0x263B82F6) : const Color(0xFFEFF6FF);
    final activeBorder = isDark
        ? const Color(0xFF3B82F6)
        : const Color(0xFF2563EB);
    final activeText = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);

    final inactiveBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final inactiveBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inactiveText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeBorder : inactiveBorder,
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isDark || isSelected
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? activeText : inactiveText,
          ),
        ),
      ),
    );
  }

  Widget _buildChapterList(
    List<StudyChapter> filtered,
    bool isDark,
    bool isHindi,
  ) {
    if (filtered.isEmpty) {
      return _buildEmptyState(isDark, isHindi);
    }

    if (!_hasParts || _selectedPartKey != null) {
      return Column(
        children: filtered
            .map(
              (chap) => _ChapterCard(
                key: ValueKey(chap.id),
                chapter: chap,
                isDark: isDark,
                isHindi: isHindi,
                onTap: () => context.push('/study/chapter/${chap.id}'),
              ),
            )
            .toList(),
      );
    }

    // Group by partKey if parts exist and no single part is filtered
    final Map<String, List<StudyChapter>> grouped = {};
    for (final c in filtered) {
      final key = c.partKey ?? '__no_part__';
      grouped.putIfAbsent(key, () => []).add(c);
    }

    final children = <Widget>[];
    for (final entry in grouped.entries) {
      final first = entry.value.first;
      final partTitle =
          first.partTitle ??
          (entry.key == '__no_part__'
              ? (isHindi ? 'सामान्य' : 'General')
              : entry.key.replaceAll('_', ' '));

      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 10.0),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                partTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entry.value.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (final chap in entry.value) {
        children.add(
          _ChapterCard(
            key: ValueKey(chap.id),
            chapter: chap,
            isDark: isDark,
            isHindi: isHindi,
            onTap: () => context.push('/study/chapter/${chap.id}'),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildEmptyState(bool isDark, bool isHindi) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final hasActiveFilter =
        _selectedFilter != ChapterFilter.all ||
        _selectedPartKey != null ||
        _searchQuery.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
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
              hasActiveFilter
                  ? Icons.filter_alt_off_rounded
                  : Icons.menu_book_rounded,
              size: 28,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasActiveFilter
                ? (isHindi
                      ? 'कोई अध्याय नहीं मिला'
                      : 'No chapters match your criteria')
                : (isHindi
                      ? 'कोई अध्याय उपलब्ध नहीं है'
                      : 'No chapters available yet'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilter
                ? (isHindi
                      ? 'कृपया अपने खोज या फ़िल्टर मानदंड बदलें।'
                      : 'Try clearing your search query or changing active filters.')
                : (isHindi
                      ? 'इस विषय के लिए जल्द ही सामग्री जोड़ी जाएगी।'
                      : 'Content will be added for this subject shortly.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          if (hasActiveFilter) ...[
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedFilter = ChapterFilter.all;
                  _selectedPartKey = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x263B82F6)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x4D3B82F6)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Text(
                  isHindi ? 'सभी फ़िल्टर साफ़ करें' : 'Clear All Filters',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF2563EB),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeletonList(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        _buildSkeletonCard(height: 140, isDark: isDark),
        const SizedBox(height: 16),
        _buildSkeletonCard(height: 48, isDark: isDark),
        const SizedBox(height: 16),
        _buildSkeletonCard(height: 110, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonCard(height: 110, isDark: isDark),
        const SizedBox(height: 12),
        _buildSkeletonCard(height: 110, isDark: isDark),
      ],
    );
  }

  Widget _buildSkeletonCard({required double height, required bool isDark}) {
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
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(shimmerColor),
          ),
        ),
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

/// Tactile interactive Chapter Card with micro-interactions, leading index
/// badge, topic count, and responsive CTA pill.
class _ChapterCard extends StatefulWidget {
  const _ChapterCard({
    super.key,
    required this.chapter,
    required this.isDark,
    required this.isHindi,
    required this.onTap,
  });

  final StudyChapter chapter;
  final bool isDark;
  final bool isHindi;
  final VoidCallback onTap;

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final isDark = widget.isDark;
    final isHindi = widget.isHindi;

    final isComplete = chapter.progressPercentage >= 100;
    final inProgress = chapter.progressPercentage > 0 && !isComplete;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    // Formatted 2-digit index (e.g. "01", "02")
    final indexFormatted = chapter.orderIndex.toString().padLeft(2, '0');

    // Status colors
    final statusColor = isComplete
        ? const Color(0xFF10B981)
        : (inProgress
              ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)));

    final statusBg = isComplete
        ? (isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5))
        : (inProgress
              ? (isDark ? const Color(0x263B82F6) : const Color(0xFFEFF6FF))
              : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: Leading index badge + Titles + Part Pill
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Index badge
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isComplete
                                      ? const Color(0x4D10B981)
                                      : (inProgress
                                            ? (isDark
                                                  ? const Color(0x4D3B82F6)
                                                  : const Color(0xFFBFDBFE))
                                            : Colors.transparent),
                                ),
                              ),
                              child: Center(
                                child: isComplete
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 22,
                                        color: Color(0xFF10B981),
                                      )
                                    : Text(
                                        indexFormatted,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: statusColor,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Chapter Title & Metadata
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (chapter.partTitle != null &&
                                      chapter.partTitle!.trim().isNotEmpty) ...[
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 5),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0x263B82F6)
                                            : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        chapter.partTitle!,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? const Color(0xFF60A5FA)
                                              : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                  ],
                                  Text(
                                    chapter.title,
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
                                  if (chapter.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      chapter.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Chevron
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 8.0,
                                top: 2.0,
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Footer row: Topic pill + Question pill + CTA Action Pill
                        Row(
                          children: [
                            _subPill(
                              icon: Icons.menu_book_rounded,
                              label:
                                  '${chapter.topicCount} ${isHindi ? "टॉपिक्स" : "Topics"}',
                              isDark: isDark,
                            ),
                            if (chapter.questionCount > 0) ...[
                              const SizedBox(width: 8),
                              _subPill(
                                icon: Icons.quiz_rounded,
                                label:
                                    '${chapter.questionCount} ${isHindi ? "प्रश्न" : "Questions"}',
                                isDark: isDark,
                              ),
                            ],
                            const Spacer(),

                            // CTA Action Pill
                            _buildCtaPill(
                              isComplete: isComplete,
                              inProgress: inProgress,
                              progress: chapter.progressPercentage,
                              isDark: isDark,
                              isHindi: isHindi,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bottom subtle progress line if in progress
                  if (inProgress) ...[
                    LinearProgressIndicator(
                      value: (chapter.progressPercentage / 100.0).clamp(
                        0.0,
                        1.0,
                      ),
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                      minHeight: 3,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _subPill({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final bg = isDark
        ? const Color(0xFF334155).withValues(alpha: 0.5)
        : const Color(0xFFF1F5F9);
    final textCol = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textCol),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textCol,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaPill({
    required bool isComplete,
    required bool inProgress,
    required double progress,
    required bool isDark,
    required bool isHindi,
  }) {
    if (isComplete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x4D10B981)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 13, color: Color(0xFF10B981)),
            const SizedBox(width: 4),
            Text(
              isHindi ? 'पूर्ण' : 'Completed',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      );
    }

    if (inProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2563EB) : const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isHindi
                  ? 'जारी रखें (${progress.toStringAsFixed(0)}%) →'
                  : 'Continue (${progress.toStringAsFixed(0)}%) →',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isHindi ? 'अध्ययन शुरू करें →' : 'Start Learning →',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }
}
