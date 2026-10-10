import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/result.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/widgets/ads/ad_banner_widget.dart';
import '../../../core/widgets/ads/rewarded_ad_prompt.dart';
import '../../group/domain/group_test_results.dart';
import '../../radio/domain/radio_track.dart';
import '../../radio/state/radio_player_controller.dart';
import '../domain/attempt_history.dart';
import '../domain/test_kind.dart';
import '../state/results_controller.dart';
import '../widgets/subject_analysis_card.dart';
import '../widgets/test_formatters.dart';
import '../widgets/topic_analysis_card.dart';

/// Redesigned Result & Post-Test Screen with high-retention performance summary,
/// visual question breakdown, live group leaderboard preview, and quick action hub.
class TestResultScreen extends StatefulWidget {
  const TestResultScreen({required this.attemptId, this.controller, super.key});

  final String attemptId;
  final ResultsController? controller;

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  late final ResultsController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? ResultsController(attemptId: widget.attemptId);
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  bool _pdfBusy = false;
  bool _retestBusy = false;

  /// Student name for the report: profile full name, else account email.
  static String _studentName() {
    final profile = ProfileService.currentProfile?.fullName.trim();
    if (profile != null && profile.isNotEmpty) return profile;
    return AuthService.currentUser?.email ?? 'Student';
  }

  Future<void> _downloadDetailedReportPdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await _c.buildDetailedReportPdf(
        studentName: _studentName(),
        studentCode: ProfileService.currentProfile?.studentCode,
      );
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'MyPrep_Report_${_c.result?.testId ?? widget.attemptId}.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report card generated successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate report card: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _reattempt() async {
    try {
      final launch = await _c.reattempt();
      if (!mounted) return;
      context.pushReplacement(
        '/attempts/${launch.attemptId}/take?test=${launch.testId}',
      );
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _startRadioRevision() async {
    if (!_c.reviewLoaded) {
      await _c.loadReview();
    }
    if (!mounted) return;
    final wrongTracks = <RadioTrack>[
      for (final q in _c.questions)
        if (_c.answerFor(q.id)?.selectedOption != _c.correctOptionFor(q.id))
          RadioTrack(question: q, correctOption: _c.correctOptionFor(q.id)),
    ];
    if (wrongTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mistakes to revise — great job!')),
      );
      return;
    }
    await RadioPlayerController.instance.loadPlaylist(
      wrongTracks,
      sourceTitle: 'Radio Revision — ${_c.test?.title ?? 'Test'}',
    );
  }

  Future<void> _retestMistakes() async {
    if (_retestBusy) return;
    setState(() => _retestBusy = true);
    try {
      final newTestId = await _c.createMistakesReTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚡ Mistake practice test ready! Starting now…'),
          backgroundColor: AppColors.success,
        ),
      );
      context.push('/tests/$newTestId');
    } catch (e) {
      if (!mounted) return;
      // Graceful fallback: Open the review screen directly if mistake self-test RPC is unavailable
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening answers review to practice mistakes…'),
          backgroundColor: AppColors.warning,
        ),
      );
      context.push('/attempts/${widget.attemptId}/review');
    } finally {
      if (mounted) setState(() => _retestBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _c.result;
    if (_c.isLoading && r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.hourglass_top,
                  size: 48,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 12),
                Text(
                  _c.error ?? 'Result not available.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _c.load, child: const Text('Retry')),
                TextButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/tests');
                    }
                  },
                  child: const Text('Back to Tests'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pct = r.percentage ?? _pct(r);
    final previous = _c.previousResult;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _c.test?.title ?? 'Test Result',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/tests');
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── BLOCK 1: PERFORMANCE SUMMARY HERO CARD ──
          _PerformanceSummaryCard(
            result: r,
            percentage: pct,
            testKindLabel: _c.kind.label,
            userRank: _c.userRank,
            totalParticipants: _c.totalParticipants,
            formattedTimeSpent: _c.formattedTimeSpent,
            formattedTotalDuration: _c.formattedTotalDuration,
          ),
          const SizedBox(height: 14),

          // ── BLOCK 2: QUESTION BREAKDOWN ROW (3 COLORED CARDS) ──
          _QuestionBreakdownRow(result: r),
          const SizedBox(height: 16),

          // ── BLOCK 3: GROUP LEADERBOARD (TOP RANKERS PREVIEW) ──
          if (_c.kind == TestKind.group || _c.leaderboard.isNotEmpty) ...[
            _LeaderboardPreviewSection(
              entries: _c.leaderboard,
              isLoading: _c.isLeaderboardLoading,
              currentUserId: r.userId,
              userScore: r.score,
              userMaxScore: r.maxScore,
              userRank: _c.userRank,
              testTitle: _c.test?.title ?? 'Test',
            ),
            const SizedBox(height: 16),
          ],

          // ── BLOCK 4: QUICK ACTION HUB ──
          _QuickActionHub(
            attemptId: widget.attemptId,
            wrongCount: r.wrongCount ?? 0,
            pdfBusy: _pdfBusy,
            retestBusy: _retestBusy,
            canReattempt: _c.canReattempt,
            attemptState: _c.attemptState,
            onReviewAnswers: () =>
                context.push('/attempts/${widget.attemptId}/review'),
            onRetestMistakes: _retestMistakes,
            onDownloadPdf: () => RewardedAdPrompt.maybeShow(
              context,
              title: 'Unlock Report Card',
              onProceed: _downloadDetailedReportPdf,
            ),
            onRadioRevision: () => RewardedAdPrompt.maybeShow(
              context,
              title: 'Unlock Radio Revision',
              onProceed: _startRadioRevision,
            ),
            onReattempt: _reattempt,
            onBackToTests: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/tests');
              }
            },
          ),
          const SizedBox(height: 16),

          const AdBannerWidget(size: AdSize.mediumRectangle),
          const SizedBox(height: 16),

          // ── DEPTH ANALYTICS (CONCEPT REVISION, SUBJECTS & TOPICS) ──
          if (_c.topicBreakdown.any(
            (t) => t.accuracy < 60 && t.attempted > 0,
          )) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.auto_stories_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                title: Text(
                  'Recommended Concept Revision',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                subtitle: Text(
                  'We identified areas with accuracy under 60%. Review theory and formulas in My Study.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                onTap: () => context.push('/study'),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (previous != null) ...[
            _ComparisonCard(
              headline: _delta(pct, previous.percentage ?? _pct(previous)),
              delta: _c.deltaFromPrevious,
              previousNumber: _c.previousEntry?.attemptNumber,
            ),
            const SizedBox(height: 14),
          ],
          if (_c.subjectBreakdown.isNotEmpty) ...[
            SubjectAnalysisCard(items: _c.subjectBreakdown),
            const SizedBox(height: 14),
          ],
          if (_c.topicBreakdown.isNotEmpty) ...[
            TopicAnalysisCard(items: _c.topicBreakdown),
            const SizedBox(height: 14),
          ],
          if (_c.attemptHistory.length > 1) ...[
            _AttemptSummaryCard(
              latest: _c.latestEntry,
              best: _c.bestEntry,
              currentAttemptId: r.attemptId,
            ),
            const SizedBox(height: 12),
            _AttemptHistoryCard(
              entries: _c.attemptHistory,
              currentAttemptId: r.attemptId,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  static double? _pct(Result r) {
    if (r.score == null || r.maxScore == null || r.maxScore == 0) return null;
    return r.score! / r.maxScore! * 100;
  }

  static String _delta(double? current, double? previous) {
    if (current == null || previous == null) {
      return 'Previous attempt available';
    }
    final d = current - previous;
    if (d.abs() < 0.05) return 'Same as your previous attempt';
    return d > 0
        ? 'Up ${d.toStringAsFixed(1)} points from your previous attempt'
        : 'Down ${d.abs().toStringAsFixed(1)} points from your previous attempt';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 1: PERFORMANCE SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceSummaryCard extends StatelessWidget {
  const _PerformanceSummaryCard({
    required this.result,
    required this.percentage,
    required this.testKindLabel,
    required this.userRank,
    required this.totalParticipants,
    required this.formattedTimeSpent,
    required this.formattedTotalDuration,
  });

  final Result result;
  final double? percentage;
  final String testKindLabel;
  final int? userRank;
  final int? totalParticipants;
  final String formattedTimeSpent;
  final String formattedTotalDuration;

  static String _num(double? v) => v == null
      ? '--'
      : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final passed = result.isPassed;
    final pctValue = (percentage ?? 0.0).clamp(0.0, 100.0);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Top badge strip: Test Type + Pass/Fail Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  testKindLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  ),
                ),
              ),
              if (passed != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: passed
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    passed ? 'Passed' : 'Needs Review',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: passed ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Central Score Gauge & Marks
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CircularProgressIndicator(
                        value: pctValue / 100.0,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                        color: passed == null
                            ? theme.colorScheme.primary
                            : (passed ? AppColors.success : const Color(0xFFEF4444)),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          percentage == null ? '--' : '${percentage!.toStringAsFixed(1)}%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Score',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Score ${_num(result.score)} / ${_num(result.maxScore)} Marks',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // 3 Key Metrics Pills: Rank, Time Taken, Accuracy
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  icon: Icons.emoji_events_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Rank',
                  value: userRank != null
                      ? '#$userRank${totalParticipants != null && totalParticipants! > 1 ? ' / $totalParticipants' : ''}'
                      : '#1',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  icon: Icons.timer_outlined,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'Time Taken',
                  value: formattedTotalDuration.isNotEmpty
                      ? '$formattedTimeSpent / $formattedTotalDuration'
                      : formattedTimeSpent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPill(
                  icon: Icons.track_changes_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Accuracy',
                  value: result.accuracy != null
                      ? '${result.accuracy!.toStringAsFixed(1)}%'
                      : '--',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 2: QUESTION BREAKDOWN ROW (3 COLORED CARDS)
// ─────────────────────────────────────────────────────────────────────────────

class _QuestionBreakdownRow extends StatelessWidget {
  const _QuestionBreakdownRow({required this.result});

  final Result result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BreakdownCard(
            count: result.correctCount ?? 0,
            label: 'Correct',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF10B981),
            bgColor: const Color(0xFFECFDF5),
            darkBgColor: const Color(0xFF064E3B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BreakdownCard(
            count: result.wrongCount ?? 0,
            label: 'Wrong',
            icon: Icons.cancel_rounded,
            color: const Color(0xFFEF4444),
            bgColor: const Color(0xFFFEF2F2),
            darkBgColor: const Color(0xFF7F1D1D),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BreakdownCard(
            count: result.unansweredCount ?? 0,
            label: 'Skipped',
            icon: Icons.remove_circle_outline_rounded,
            color: const Color(0xFFF59E0B),
            bgColor: const Color(0xFFFFFBEB),
            darkBgColor: const Color(0xFF78350F),
          ),
        ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.darkBgColor,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color darkBgColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? darkBgColor.withValues(alpha: 0.35) : bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.25),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 3: GROUP LEADERBOARD (TOP RANKERS PREVIEW & BOTTOM SHEET)
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderboardPreviewSection extends StatelessWidget {
  const _LeaderboardPreviewSection({
    required this.entries,
    required this.isLoading,
    required this.currentUserId,
    required this.userScore,
    required this.userMaxScore,
    required this.userRank,
    required this.testTitle,
  });

  final List<LeaderboardEntry> entries;
  final bool isLoading;
  final String currentUserId;
  final double? userScore;
  final double? userMaxScore;
  final int? userRank;
  final String testTitle;

  static String _num(double? v) => v == null
      ? '--'
      : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  size: 20,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Group Leaderboard',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      entries.isNotEmpty
                          ? '${entries.length} participants scored'
                          : 'Peer rankings and standings',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (isLoading) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ] else if (entries.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Color(0xFF64748B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Peer results will appear here as group members complete their attempts.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Top 3 Podium Cards
            _buildPodium(context),
            const SizedBox(height: 14),

            // If user is outside top 3, show user's standing chip
            if (userRank != null && userRank! > 3) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$userRank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Your Current Rank',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${_num(userScore)} / ${_num(userMaxScore)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],

            // Full Leaderboard Action Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openFullLeaderboardSheet(context),
                icon: const Icon(Icons.leaderboard_rounded, size: 18),
                label: const Text('🏆 Full Leaderboard Dekhein'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPodium(BuildContext context) {
    final top3 = entries.take(3).toList();
    if (top3.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 2nd Place (Left)
        if (top3.length > 1)
          Expanded(child: _PodiumPillar(entry: top3[1], place: 2))
        else
          const Spacer(),

        // 1st Place (Center)
        Expanded(child: _PodiumPillar(entry: top3[0], place: 1)),

        // 3rd Place (Right)
        if (top3.length > 2)
          Expanded(child: _PodiumPillar(entry: top3[2], place: 3))
        else
          const Spacer(),
      ],
    );
  }

  void _openFullLeaderboardSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FullLeaderboardSheet(
        entries: entries,
        currentUserId: currentUserId,
        testTitle: testTitle,
      ),
    );
  }
}

class _PodiumPillar extends StatelessWidget {
  const _PodiumPillar({required this.entry, required this.place});

  final LeaderboardEntry entry;
  final int place;

  static String _num(double? v) => v == null
      ? '--'
      : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color badgeColor;
    final String medalEmoji;
    final double pillarHeight;

    switch (place) {
      case 1:
        badgeColor = const Color(0xFFF59E0B);
        medalEmoji = '🥇';
        pillarHeight = 78;
      case 2:
        badgeColor = const Color(0xFF94A3B8);
        medalEmoji = '🥈';
        pillarHeight = 62;
      case 3:
      default:
        badgeColor = const Color(0xFFD97706);
        medalEmoji = '🥉';
        pillarHeight = 52;
    }

    final avatarUrl = entry.avatarUrl;
    final initial = (entry.label.isNotEmpty ? entry.label[0] : '?').toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: place == 1 ? 24 : 20,
              backgroundColor: badgeColor.withValues(alpha: 0.2),
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: place == 1 ? 16 : 14,
                        color: badgeColor,
                      ),
                    )
                  : null,
            ),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Text(medalEmoji, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entry.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: entry.isCurrentUser ? FontWeight.bold : FontWeight.w500,
            color: entry.isCurrentUser ? const Color(0xFF3B82F6) : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          '${_num(entry.score)} pts',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: pillarHeight,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: isDark ? 0.18 : 0.12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Text(
            '#$place',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: badgeColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _FullLeaderboardSheet extends StatelessWidget {
  const _FullLeaderboardSheet({
    required this.entries,
    required this.currentUserId,
    required this.testTitle,
  });

  final List<LeaderboardEntry> entries;
  final String currentUserId;
  final String testTitle;

  static String _num(double? v) => v == null
      ? '--'
      : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

  static String _fmtTime(int? sec) {
    if (sec == null || sec <= 0) return '--';
    final m = sec ~/ 60;
    final s = sec % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Official Test Leaderboard',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            testTitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Participants List
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    final isMe = e.userId == currentUserId || e.isCurrentUser;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMe
                            ? (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF))
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isMe
                              ? const Color(0xFF3B82F6)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          width: isMe ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Rank badge
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: e.rank == 1
                                  ? const Color(0xFFF59E0B)
                                  : (e.rank == 2
                                      ? const Color(0xFF94A3B8)
                                      : (e.rank == 3
                                          ? const Color(0xFFD97706)
                                          : (isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFE2E8F0)))),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${e.rank}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: e.rank <= 3
                                    ? Colors.white
                                    : (isDark ? Colors.white : const Color(0xFF334155)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Avatar
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                            backgroundImage: e.avatarUrl != null && e.avatarUrl!.isNotEmpty
                                ? NetworkImage(e.avatarUrl!)
                                : null,
                            child: e.avatarUrl == null || e.avatarUrl!.isEmpty
                                ? Text(
                                    (e.label.isNotEmpty ? e.label[0] : '?').toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),

                          // Name & Time Taken
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        e.label,
                                        style: TextStyle(
                                          fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'YOU',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '⏱️ ${_fmtTime(e.timeTakenSeconds)}${e.accuracy != null ? ' · 🎯 ${e.accuracy!.toStringAsFixed(1)}%' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Score
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_num(e.score)} / ${_num(e.maxScore)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (e.percentage != null)
                                Text(
                                  '${e.percentage!.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 4: QUICK ACTION HUB
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionHub extends StatelessWidget {
  const _QuickActionHub({
    required this.attemptId,
    required this.wrongCount,
    required this.pdfBusy,
    required this.retestBusy,
    required this.canReattempt,
    required this.attemptState,
    required this.onReviewAnswers,
    required this.onRetestMistakes,
    required this.onDownloadPdf,
    required this.onRadioRevision,
    required this.onReattempt,
    required this.onBackToTests,
  });

  final String attemptId;
  final int wrongCount;
  final bool pdfBusy;
  final bool retestBusy;
  final bool canReattempt;
  final dynamic attemptState;
  final VoidCallback onReviewAnswers;
  final VoidCallback onRetestMistakes;
  final VoidCallback onDownloadPdf;
  final VoidCallback onRadioRevision;
  final VoidCallback onReattempt;
  final VoidCallback onBackToTests;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Primary Full-Width Action: Review Answers & Explanations
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            key: const Key('review_answers_button'),
            onPressed: onReviewAnswers,
            icon: const Icon(Icons.menu_book_rounded, size: 20),
            label: const Text(
              'Review Answers',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 2. Accent Full-Width Action: Re-test Only Mistakes (if wrongCount > 0)
        if (wrongCount > 0) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.tonalIcon(
              key: const Key('retest_mistakes_button'),
              onPressed: retestBusy ? null : onRetestMistakes,
              icon: retestBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_rounded, size: 20, color: Color(0xFFD97706)),
              label: Text(
                retestBusy
                    ? 'Preparing Re-test Session…'
                    : '⚡ Re-test Only Mistakes ($wrongCount Qs)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD97706),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFEF3C7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 3. Secondary Utility Row: PDF Report & Radio Audio Revision
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  key: const Key('download_result_pdf'),
                  onPressed: pdfBusy ? null : onDownloadPdf,
                  icon: pdfBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(
                    pdfBusy ? 'Generating…' : '📄 PDF Report',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  key: const Key('radio_revision_button'),
                  onPressed: onRadioRevision,
                  icon: const Icon(Icons.radio_rounded, size: 18),
                  label: const Text(
                    '📻 Radio Audio',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4. Re-attempt full test (if permitted by policy)
        if (canReattempt) ...[
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onReattempt,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text(
                '🔄 Re-attempt Full Test',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else if (attemptState != null && attemptState.hasAnyAttempt) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              attemptState.settings.allowReattempt
                  ? '${attemptState.usageLabel} · Re-attempt limit reached'
                  : 'This test allows a single attempt',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 4),
        ],

        // 5. Back to Tests button
        TextButton(
          onPressed: onBackToTests,
          child: const Text('Back to Tests'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ATTEMPT COMPARISON & HISTORY HELPERS (PRESERVED)
// ─────────────────────────────────────────────────────────────────────────────

String _fmtNum(double? v) => v == null
    ? '--'
    : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

String _signed(num v, {String suffix = ''}) {
  final s = v is int ? '$v' : _fmtNum(v.toDouble());
  return (v > 0 ? '+$s' : s) + suffix;
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.headline,
    required this.delta,
    required this.previousNumber,
  });

  final String headline;
  final ResultDelta? delta;
  final int? previousNumber;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final rows = <(String, String)>[
      if (d?.score != null) ('Marks', _signed(d!.score!)),
      if (d?.percentage != null)
        ('Percentage', _signed(d!.percentage!, suffix: ' pts')),
      if (d?.accuracy != null)
        ('Accuracy', _signed(d!.accuracy!, suffix: ' pts')),
      if (d?.correct != null) ('Correct', _signed(d!.correct!)),
      if (d?.wrong != null) ('Wrong', _signed(d!.wrong!)),
      if (d?.unanswered != null) ('Unanswered', _signed(d!.unanswered!)),
      if (d?.time != null)
        (
          'Time',
          '${d!.time!.isNegative ? '-' : '+'}${_fmtDuration(d.time!.abs())}',
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    previousNumber == null
                        ? 'Compared with previous attempt'
                        : 'Compared with attempt $previousNumber',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(headline),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(label), Text(value)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttemptSummaryCard extends StatelessWidget {
  const _AttemptSummaryCard({
    required this.latest,
    required this.best,
    required this.currentAttemptId,
  });

  final AttemptHistoryEntry? latest;
  final AttemptHistoryEntry? best;
  final String currentAttemptId;

  String _line(AttemptHistoryEntry e) {
    final n = e.attemptNumber == null ? '' : 'Attempt ${e.attemptNumber} · ';
    final r = e.result;
    final pct = r.percentage == null ? '' : ' (${_fmtNum(r.percentage)}%)';
    return '$n${_fmtNum(r.score)} / ${_fmtNum(r.maxScore)}$pct';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          if (latest != null)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Latest Attempt'),
              subtitle: Text(_line(latest!)),
              trailing: latest!.result.attemptId == currentAttemptId
                  ? const Text('Viewing')
                  : null,
            ),
          if (best != null)
            ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('Best Attempt'),
              subtitle: Text(_line(best!)),
              trailing: best!.result.attemptId == currentAttemptId
                  ? const Text('Viewing')
                  : null,
            ),
        ],
      ),
    );
  }
}

class _AttemptHistoryCard extends StatelessWidget {
  const _AttemptHistoryCard({
    required this.entries,
    required this.currentAttemptId,
  });

  final List<AttemptHistoryEntry> entries;
  final String currentAttemptId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attempt History',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final e in entries.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: e.result.attemptId == currentAttemptId
                      ? null
                      : () => context.push(
                          '/attempts/${e.result.attemptId}/result',
                        ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.attemptNumber == null
                                  ? 'Attempt'
                                  : 'Attempt ${e.attemptNumber}'
                                        '${e.result.attemptId == currentAttemptId ? ' (current)' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${_fmtNum(e.result.score)} / ${_fmtNum(e.result.maxScore)}'
                              '${e.result.percentage == null ? '' : ' · ${_fmtNum(e.result.percentage)}%'}'
                              '${e.result.accuracy == null ? '' : ' · acc ${_fmtNum(e.result.accuracy)}%'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'C ${e.result.correctCount ?? '--'} · W ${e.result.wrongCount ?? '--'} · U ${e.result.unansweredCount ?? '--'}'
                              '${e.duration == null ? '' : ' · ${_fmtDuration(e.duration!)}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (e.completedAt != null)
                        Text(
                          TestFormatters.dateTime(e.completedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
