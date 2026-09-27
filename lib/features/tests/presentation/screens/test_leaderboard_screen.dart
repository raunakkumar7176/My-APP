import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/app_error.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/profile_service.dart';
import '../../domain/test_pdf_export_service.dart';
import '../widgets/common/test_card.dart';

/// Leaderboard participant entry.
class TestLeaderboardParticipant {
  const TestLeaderboardParticipant({
    required this.rank,
    required this.name,
    required this.studentCode,
    required this.score,
    required this.totalMarks,
    required this.accuracy,
    required this.timeTaken,
    this.avatarUrl,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;
  final String studentCode;
  final double score;
  final double totalMarks;
  final double accuracy;
  final String timeTaken;
  final String? avatarUrl;
  final bool isCurrentUser;
}

/// Screen 6: Leaderboard & Export Hub
/// - Respects `is_result_published` gate.
/// - If unpublished: Displays "Results will be published by cohort leader".
/// - If published: Top 3 Podium cards, sticky "My Rank" strip, full participant list.
/// - Export Section: Download actions for PDF Scorecard and Solution Booklet.
class TestLeaderboardScreen extends StatefulWidget {
  const TestLeaderboardScreen({
    this.testId,
    this.testData,
    this.isResultPublished = true,
    this.participants,
    super.key,
  });

  final String? testId;
  final TestCardData? testData;
  final bool isResultPublished;
  final List<TestLeaderboardParticipant>? participants;

  @override
  State<TestLeaderboardScreen> createState() => _TestLeaderboardScreenState();
}

class _TestLeaderboardScreenState extends State<TestLeaderboardScreen> {
  late final TestCardData _test;
  late bool _published;
  late final List<TestLeaderboardParticipant> _participants;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    final tid = widget.testId ?? widget.testData?.id ?? 'leaderboard_default';
    _test =
        widget.testData ??
        TestCardData(
          id: tid,
          title: 'Modern Indian History: Freedom Struggle & Gandhian Era',
          subject: 'History',
          difficulty: TestCardDifficulty.medium,
          mode: 'Exam Simulation',
          questionCount: 25,
          totalMarks: 50.0,
          durationMinutes: 35,
          status: TestCardStatus.completed,
          scoreObtained: 42.0,
          accuracyPercentage: 84.0,
          rank: 4,
          totalParticipants: 48,
        );

    _published = widget.isResultPublished;
    _participants = widget.participants ?? _buildSampleParticipants();
  }

  List<TestLeaderboardParticipant> _buildSampleParticipants() {
    return const [
      TestLeaderboardParticipant(
        rank: 1,
        name: 'Aarav Sharma',
        studentCode: 'MP-91024',
        score: 48.0,
        totalMarks: 50.0,
        accuracy: 96.0,
        timeTaken: '24m 12s',
      ),
      TestLeaderboardParticipant(
        rank: 2,
        name: 'Priya Patel',
        studentCode: 'MP-83719',
        score: 46.0,
        totalMarks: 50.0,
        accuracy: 92.0,
        timeTaken: '26m 40s',
      ),
      TestLeaderboardParticipant(
        rank: 3,
        name: 'Rohan Verma',
        studentCode: 'MP-77215',
        score: 44.0,
        totalMarks: 50.0,
        accuracy: 88.0,
        timeTaken: '29m 05s',
      ),
      TestLeaderboardParticipant(
        rank: 4,
        name: 'You (Current Student)',
        studentCode: 'MP-65432',
        score: 42.0,
        totalMarks: 50.0,
        accuracy: 84.0,
        timeTaken: '28m 45s',
        isCurrentUser: true,
      ),
      TestLeaderboardParticipant(
        rank: 5,
        name: 'Ananya Gupta',
        studentCode: 'MP-54129',
        score: 40.0,
        totalMarks: 50.0,
        accuracy: 80.0,
        timeTaken: '31m 10s',
      ),
      TestLeaderboardParticipant(
        rank: 6,
        name: 'Vikramaditya Roy',
        studentCode: 'MP-41298',
        score: 38.0,
        totalMarks: 50.0,
        accuracy: 76.0,
        timeTaken: '33m 50s',
      ),
    ];
  }

  static String _candidateName() {
    final profile = ProfileService.currentProfile?.fullName.trim();
    if (profile != null && profile.isNotEmpty) return profile;
    return AuthService.currentUser?.email ?? 'Student';
  }

  Future<void> _onDownloadScorecard() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await TestPdfExportService.buildScorecard(
        data: _test,
        candidateName: _candidateName(),
        studentCode: ProfileService.currentProfile?.studentCode,
      );
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: '${_test.title} - scorecard.pdf');
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate the scorecard PDF. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  void _onDownloadSolutionBooklet() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'The Solution Booklet is coming soon — not available yet.',
        ),
        backgroundColor: Color(0xFF64748B),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cohort Leaderboard & Analytics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: !_published
          ? _buildUnpublishedView(isDark)
          : SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Summary Strip
                        _buildHeaderSummary(isDark),
                        const SizedBox(height: 16),

                        // Sticky "My Rank" Highlight Card
                        _buildMyRankHighlight(theme, isDark),
                        const SizedBox(height: 20),

                        // Top 3 Podium
                        _buildPodiumSection(isDark),
                        const SizedBox(height: 24),

                        // Full Participant Leaderboard
                        _buildParticipantList(isDark),
                        const SizedBox(height: 24),

                        // Export Hub Section
                        _buildExportHubSection(isDark),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Unpublished Gate View ──
  Widget _buildUnpublishedView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.5)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                size: 56,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Results Awaiting Cohort Leader Release',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Results will be published by cohort leader once all test submissions and integrity reviews are concluded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFD97706).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Expected Release: Today at 06:00 PM',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _published = true); // Toggle preview for testing
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check for Updates'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSummary(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _test.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.people_outline_rounded,
                size: 15,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 4),
              Text(
                '${_test.totalParticipants ?? 48} Aspirants Appeared',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
              const SizedBox(width: 10),
              const Icon(
                Icons.insights_rounded,
                size: 15,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 4),
              const Text(
                'Avg Score: 32.4 M',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyRankHighlight(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A8A), const Color(0xFF1E293B)]
              : [const Color(0xFFDBEAFE), const Color(0xFFEFF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.military_tech_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR STANDING: RANK #4',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1D4ED8),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Score: 42.0 M • 84% Accuracy',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Top 8% of cohort • Faster than 82% of students',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top 3 Podium Cards ──
  Widget _buildPodiumSection(bool isDark) {
    if (_participants.length < 3) return const SizedBox.shrink();

    final r1 = _participants[0];
    final r2 = _participants[1];
    final r3 = _participants[2];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Rank 2 (Silver)
        Expanded(
          child: _podiumCard(
            participant: r2,
            badgeColor: const Color(0xFF94A3B8),
            badgeTitle: '🥈 #2',
            height: 140,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),

        // Rank 1 (Gold)
        Expanded(
          child: _podiumCard(
            participant: r1,
            badgeColor: const Color(0xFFF59E0B),
            badgeTitle: '👑 #1',
            height: 165,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),

        // Rank 3 (Bronze)
        Expanded(
          child: _podiumCard(
            participant: r3,
            badgeColor: const Color(0xFFD97706),
            badgeTitle: '🥉 #3',
            height: 130,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _podiumCard({
    required TestLeaderboardParticipant participant,
    required Color badgeColor,
    required String badgeTitle,
    required double height,
    required bool isDark,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            badgeTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: badgeColor.withValues(alpha: 0.15),
            child: Text(
              participant.name[0],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: badgeColor,
              ),
            ),
          ),
          Text(
            participant.name.split(' ').first,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${participant.score.toInt()} M',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantList(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'ALL PARTICIPANTS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const Divider(height: 1),
          ..._participants.map((p) {
            return Container(
              color: p.isCurrentUser
                  ? const Color(0xFF2563EB).withValues(alpha: 0.08)
                  : Colors.transparent,
              child: ListTile(
                leading: SizedBox(
                  width: 34,
                  child: Text(
                    '#${p.rank}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: p.rank <= 3
                          ? const Color(0xFFF59E0B)
                          : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B)),
                    ),
                  ),
                ),
                title: Text(
                  p.name,
                  style: TextStyle(
                    fontWeight: p.isCurrentUser
                        ? FontWeight.bold
                        : FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                subtitle: Text(
                  '${p.studentCode} • ${p.timeTaken}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${p.score.toStringAsFixed(1)} Marks',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${p.accuracy.toStringAsFixed(0)}% Acc',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildExportHubSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.file_download_outlined,
                color: Color(0xFF2563EB),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'EXPORT HUB & ARCHIVAL',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Generate official offline PDF documents for your personal study binder:',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),

          // Download Buttons
          OutlinedButton.icon(
            key: const Key('download_scorecard_pdf_btn'),
            onPressed: _pdfBusy ? null : _onDownloadScorecard,
            icon: _pdfBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text('📄 Download Verified Scorecard (PDF)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('download_solutions_booklet_btn'),
            onPressed: _onDownloadSolutionBooklet,
            icon: const Icon(Icons.auto_stories_rounded, size: 18),
            label: const Text('📘 Download Complete Solution Booklet (PDF)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
