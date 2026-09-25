import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/profile_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../study/data/study_repository.dart';
import '../../study/domain/continue_learning.dart';

/// Card for the "Continue Studying" section on the Home / Dashboard.
/// Displays the student's most recent topic/chapter with progress and
/// a one-tap "Continue →" action to resume learning.
class ContinueStudyingCard extends StatefulWidget {
  const ContinueStudyingCard({
    super.key,
    this.repository,
    this.userId,
    this.languageCode = 'en',
  });

  final StudyRepository? repository;
  final String? userId;
  final String languageCode;

  @override
  State<ContinueStudyingCard> createState() => _ContinueStudyingCardState();
}

class _ContinueStudyingCardState extends State<ContinueStudyingCard> {
  late final StudyRepository _repo;
  bool _loading = true;
  ContinueLearningSnapshot? _snapshot;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? const SupabaseStudyRepository();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    setState(() => _loading = true);

    String? uid = widget.userId;
    if (uid == null) {
      try {
        uid = ProfileService.currentProfile?.id;
        if (uid == null && SupabaseService.isInitialized) {
          uid = SupabaseService.client.auth.currentUser?.id;
        }
      } catch (_) {
        // Safe fallback in test or unauthenticated environments.
      }
    }

    if (uid == null || uid.isEmpty) {
      if (mounted) {
        setState(() {
          _snapshot = null;
          _loading = false;
        });
      }
      return;
    }

    try {
      final snap = await _repo.fetchRecentStudyProgress(
        userId: uid,
        languageCode: widget.languageCode,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    if (_loading) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Empty state: No recent topic studied yet
    if (_snapshot == null) {
      return Container(
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
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.menu_book_outlined,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Start your first lesson',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Explore syllabus, chapter theory, and practice questions.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => context.push('/study'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Explore', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    final snap = _snapshot!;
    final pct = (snap.progressPercentage / 100.0).clamp(0.0, 1.0);

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            if (snap.topicId.isNotEmpty) {
              final chapterQuery = snap.chapterId.isNotEmpty
                  ? '?chapterId=${snap.chapterId}'
                  : '';
              context.push('/study/topic/${snap.topicId}$chapterQuery');
            } else if (snap.chapterId.isNotEmpty) {
              context.push('/study/chapter/${snap.chapterId}');
            } else {
              context.push('/study');
            }
          },
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
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        snap.subjectName.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(pct * 100).toInt()}% Done',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  snap.topicTitle.isNotEmpty
                      ? snap.topicTitle
                      : snap.chapterTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (snap.chapterTitle.isNotEmpty &&
                    snap.topicTitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    snap.chapterTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFEEF2F6),
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      snap.lastStudiedAt != null
                          ? 'Recently visited'
                          : 'In progress',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Continue',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
