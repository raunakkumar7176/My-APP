import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/study_repository.dart';
import '../controllers/topic_theory_controller.dart';
import '../widgets/content_block_renderer.dart';

/// Distraction-free, academic Digital Textbook & Theory Reader.
///
/// Designed with high-focus typography, mathematical formula callouts,
/// real-time scroll progress, topic traversal, and seamless practice integration.
class TopicTheoryScreen extends StatefulWidget {
  const TopicTheoryScreen({
    super.key,
    required this.topicId,
    required this.chapterId,
    this.repository,
    this.controller,
  });

  final String topicId;
  final String chapterId;
  final StudyRepository? repository;
  final TopicTheoryController? controller;

  @override
  State<TopicTheoryScreen> createState() => _TopicTheoryScreenState();
}

class _TopicTheoryScreenState extends State<TopicTheoryScreen> {
  late final TopicTheoryController _controller;
  final ScrollController _scrollController = ScrollController();
  bool _isBookmarked = false;
  double _scrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        TopicTheoryController(
          initialTopicId: widget.topicId,
          chapterId: widget.chapterId,
          repository: widget.repository,
        );
    _controller.addListener(_onControllerUpdate);
    _scrollController.addListener(_onScroll);

    // Initial load if not already provided with data
    if (widget.controller == null || _controller.topic == null) {
      _controller.load();
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final progress = maxScroll > 0
        ? (currentScroll / maxScroll).clamp(0.0, 1.0)
        : 0.0;

    if ((progress - _scrollProgress).abs() > 0.02 ||
        progress == 1.0 ||
        progress == 0.0) {
      setState(() {
        _scrollProgress = progress;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.removeListener(_onControllerUpdate);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isHindi = _controller.isHindi;
    final topic = _controller.topic;
    final chapter = _controller.chapter;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final headerBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final primaryAccent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 54,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 19,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 8,
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _buildBreadcrumb(chapter, isHindi),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              topic?.title ?? (isHindi ? 'विषय सामग्री' : 'Topic Theory'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        actions: [
          // Language Switch Pill
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadius.pillBorder,
                onTap: () {
                  final next = _controller.languageCode == 'en' ? 'hi' : 'en';
                  _controller.setLanguage(next);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x333B82F6)
                        : const Color(0xFFEFF6FF),
                    borderRadius: AppRadius.pillBorder,
                    border: Border.all(color: primaryAccent.withAlpha(120)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        size: 13,
                        color: primaryAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isHindi ? 'HI' : 'EN',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Bookmark Button
          IconButton(
            icon: Icon(
              _isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              size: 21,
              color: _isBookmarked ? primaryAccent : textSecondary,
            ),
            tooltip: isHindi ? 'बुकमार्क' : 'Bookmark topic',
            onPressed: () {
              setState(() {
                _isBookmarked = !_isBookmarked;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isBookmarked
                        ? (isHindi
                              ? 'टॉपिक बुकमार्क किया गया'
                              : 'Topic bookmarked')
                        : (isHindi ? 'बुकमार्क हटाया गया' : 'Bookmark removed'),
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: _scrollProgress,
            minHeight: 3,
            backgroundColor: isDark
                ? const Color(0xFF1E293B)
                : const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SelectionArea(child: _buildBody(context, isDark, isHindi)),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context, isDark, isHindi),
    );
  }

  String _buildBreadcrumb(dynamic chapter, bool isHindi) {
    if (chapter != null) {
      final part =
          chapter.partTitle != null &&
              chapter.partTitle!.toString().trim().isNotEmpty
          ? chapter.partTitle.toString()
          : (isHindi ? 'विषय' : 'Subject');
      return '$part • ${chapter.title}';
    }
    return isHindi ? 'अध्याय • डिजिटल पाठ्यपुस्तक' : 'Chapter • Digital Reader';
  }

  // ── Body & Content Dispatcher ─────────────────────────────────────────────
  Widget _buildBody(BuildContext context, bool isDark, bool isHindi) {
    if (_controller.isLoading && _controller.contentBlocks.isEmpty) {
      return _buildSkeletonReader(isDark);
    }

    if (_controller.errorMessage != null && _controller.contentBlocks.isEmpty) {
      return _buildErrorState(isDark, isHindi);
    }

    final blocks = _controller.contentBlocks;
    if (blocks.isEmpty) {
      return _buildEmptyState(isDark, isHindi);
    }

    final topic = _controller.topic;
    final estimatedMin = topic?.estimatedMinutes ?? 10;
    final progressPercent = (_scrollProgress * 100).toInt();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 96.0),
      itemCount: blocks.length + 6,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTopicMetaHeader(
            progressPercent: progressPercent,
            estimatedMinutes: estimatedMin,
            isCompleted: _controller.isCompleted,
            isDark: isDark,
            isHindi: isHindi,
          );
        }
        if (index == 1) return const SizedBox(height: 18);
        if (index < blocks.length + 2) {
          final block = blocks[index - 2];
          return ContentBlockRenderer(
            key: ValueKey(block.id),
            block: block,
            isHindi: isHindi,
          );
        }
        if (index == blocks.length + 2) return const SizedBox(height: 24);
        if (index == blocks.length + 3) {
          return _buildTopicPracticeCard(isDark, isHindi);
        }
        if (index == blocks.length + 4) return const SizedBox(height: 16);
        return _buildTopicTraversalBar(isDark, isHindi);
      },
    );
  }

  // ── Topic Metadata Header Bar ──────────────────────────────────────────────
  Widget _buildTopicMetaHeader({
    required int progressPercent,
    required int estimatedMinutes,
    required bool isCompleted,
    required bool isDark,
    required bool isHindi,
  }) {
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 15,
                color: isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Text(
                isHindi
                    ? 'अध्ययन प्रगति: $progressPercent% • ⏱️ $estimatedMinutes मिनट'
                    : 'Topic Progress: $progressPercent% • ⏱️ $estimatedMinutes min read',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isCompleted
                  ? (isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5))
                  : (isDark
                        ? const Color(0x263B82F6)
                        : const Color(0xFFEFF6FF)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isCompleted
                  ? (isHindi ? '✓ पूर्ण' : '✓ Completed')
                  : (isHindi ? 'अध्ययन जारी' : 'In Progress'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isCompleted
                    ? const Color(0xFF10B981)
                    : (isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF2563EB)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── End of Topic Practice Card ─────────────────────────────────────────────
  Widget _buildTopicPracticeCard(bool isDark, bool isHindi) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final primaryAccent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x333B82F6)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.quiz_rounded, size: 20, color: primaryAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHindi ? 'विषय अभ्यास टेस्ट' : 'Test Your Understanding',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHindi
                          ? 'इस विषय के प्रश्नों से अपनी समझ को परखें।'
                          : 'Solidify your knowledge with targeted MCQs.',
                      style: TextStyle(fontSize: 12.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: AppButton.primary(
              label: isHindi
                  ? 'विषय अभ्यास शुरू करें →'
                  : 'Practice This Topic →',
              onPressed: () {
                final practiceExtra = {
                  'chapterId': widget.chapterId,
                  'topicTitle': _controller.topic?.title,
                  'chapterTitle': _controller.chapter?.title,
                  'subjectTitle': _controller.chapter?.partTitle,
                  'subjectId': _controller.chapter?.subjectId,
                };

                context.push(
                  '/study/topic/${_controller.currentTopicId}/practice?chapterId=${widget.chapterId}',
                  extra: practiceExtra,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Topic Traversal Bar (Previous & Next Topic) ─────────────────────────────
  Widget _buildTopicTraversalBar(bool isDark, bool isHindi) {
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final primaryAccent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);

    final hasPrev = _controller.hasPrevious;
    final hasNext = _controller.hasNext;

    return Row(
      children: [
        // Previous Button
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: hasPrev
                  ? () {
                      _controller.goToPreviousTopic();
                      _scrollController.jumpTo(0);
                    }
                  : null,
              child: Opacity(
                opacity: hasPrev ? 1.0 : 0.45,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 17,
                        color: hasPrev ? textPrimary : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isHindi ? 'पिछला विषय' : 'Previous Topic',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                            if (hasPrev && _controller.previousTopic != null)
                              Text(
                                _controller.previousTopic!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Next Button OR Chapter Complete
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: hasNext
                  ? () {
                      _controller.goToNextTopic();
                      _scrollController.jumpTo(0);
                    }
                  : () {
                      // Last topic: navigate back or to chapter hub
                      Navigator.of(context).maybePop();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: hasNext
                      ? cardBg
                      : (isDark
                            ? const Color(0x2610B981)
                            : const Color(0xFFECFDF5)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasNext
                        ? borderColor
                        : const Color(0xFF10B981).withAlpha(120),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hasNext
                                ? (isHindi ? 'अगला विषय' : 'Next Topic')
                                : (isHindi
                                      ? 'अध्याय पूर्ण 🎉'
                                      : 'Chapter Complete 🎉'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: hasNext
                                  ? textSecondary
                                  : const Color(0xFF10B981),
                            ),
                          ),
                          if (hasNext && _controller.nextTopic != null)
                            Text(
                              _controller.nextTopic!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            )
                          else if (!hasNext)
                            Text(
                              isHindi
                                  ? 'हब पर वापस जाएँ'
                                  : 'Return to Chapter Hub',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      hasNext
                          ? Icons.arrow_forward_rounded
                          : Icons.check_circle_rounded,
                      size: 17,
                      color: hasNext ? primaryAccent : const Color(0xFF10B981),
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

  // ── Fixed Floating Bottom Bar ──────────────────────────────────────────────
  Widget _buildBottomBar(BuildContext context, bool isDark, bool isHindi) {
    final isDone = _controller.isCompleted;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(top: BorderSide(color: borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 12),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Quick Previous
                IconButton.outlined(
                  icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  tooltip: isHindi ? 'पिछला टॉपिक' : 'Previous Topic',
                  onPressed: _controller.hasPrevious
                      ? () {
                          _controller.goToPreviousTopic();
                          _scrollController.jumpTo(0);
                        }
                      : null,
                ),
                const SizedBox(width: 10),

                // Mark Completed primary CTA
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: isDone
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isDark
                                  ? const Color(0x2610B981)
                                  : const Color(0xFFECFDF5),
                              side: const BorderSide(
                                color: Color(0xFF10B981),
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _controller.isSavingProgress
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Color(0xFF10B981),
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: Color(0xFF10B981),
                                  ),
                            label: Text(
                              isHindi ? '✓ पूर्ण चिह्नित' : '✓ Completed',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            onPressed: _controller.isSavingProgress
                                ? null
                                : () => _controller.toggleCompletion(),
                          )
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _controller.isSavingProgress
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              isHindi
                                  ? 'पूर्ण के रूप में चिह्नित करें'
                                  : 'Mark as Completed',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: _controller.isSavingProgress
                                ? null
                                : () => _controller.toggleCompletion(),
                          ),
                  ),
                ),
                const SizedBox(width: 10),

                // Quick Next
                IconButton.outlined(
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  tooltip: isHindi ? 'अगला टॉपिक' : 'Next Topic',
                  onPressed: _controller.hasNext
                      ? () {
                          _controller.goToNextTopic();
                          _scrollController.jumpTo(0);
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Skeletons, Error, and Empty States ─────────────────────────────────────
  Widget _buildSkeletonReader(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSkeletonBox(height: 38, isDark: isDark),
        const SizedBox(height: 16),
        _buildSkeletonBox(height: 24, width: 220, isDark: isDark),
        const SizedBox(height: 10),
        _buildSkeletonBox(height: 80, isDark: isDark),
        const SizedBox(height: 16),
        _buildSkeletonBox(height: 110, isDark: isDark),
        const SizedBox(height: 16),
        _buildSkeletonBox(height: 60, isDark: isDark),
      ],
    );
  }

  Widget _buildSkeletonBox({
    required double height,
    double? width,
    required bool isDark,
  }) {
    final baseColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
    );
  }

  Widget _buildErrorState(bool isDark, bool isHindi) {
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x33DC2626)
                    : const Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 28,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _controller.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: textSecondary,
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
    );
  }

  Widget _buildEmptyState(bool isDark, bool isHindi) {
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF334155).withAlpha(120)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 28,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isHindi
                  ? 'कोई सामग्री उपलब्ध नहीं है'
                  : 'No content blocks loaded',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isHindi
                  ? 'इस टॉपिक के लिए सामग्री जल्द ही जोड़ी जाएगी।'
                  : 'Content will be added for this topic shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textSecondary),
            ),
            const SizedBox(height: 18),
            AppButton.secondary(
              label: isHindi ? 'पुनः लोड करें' : 'Reload',
              onPressed: () => _controller.load(),
            ),
          ],
        ),
      ),
    );
  }
}
