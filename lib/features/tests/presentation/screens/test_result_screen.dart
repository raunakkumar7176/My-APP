import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/app_error.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/profile_service.dart';
import '../../data/coach_report_repository.dart';
import '../../domain/coach_diagnostic.dart';
import '../../domain/test_pdf_export_service.dart';
import '../widgets/common/result_metric_card.dart';
import '../widgets/common/test_card.dart';

/// Performance Solution model for post-exam review.
class ExamSolutionItem {
  const ExamSolutionItem({
    required this.questionNumber,
    required this.topic,
    required this.statement,
    required this.options,
    required this.correctIndex,
    required this.userIndex, // -1 if unattempted
    required this.explanation,
  });

  final int questionNumber;
  final String topic;
  final String statement;
  final List<String> options;
  final int correctIndex;
  final int userIndex;
  final String explanation;

  bool get isCorrect => userIndex == correctIndex;
  bool get isUnattempted => userIndex < 0;
  bool get isIncorrect => !isCorrect && !isUnattempted;
}

/// Screen 5: Performance Scorecard & Solutions
/// Comprehensive evaluation with:
/// - Hero Score Ring Card with celebratory points pill
/// - Horizontal Segmented Bar (Correct, Incorrect, Unattempted)
/// - Topic Mastery Matrix (Strong vs Topics needing revision)
/// - Filterable solutions review with in-depth explanation accordions
/// - AI Coach tab reading pre-stored diagnostics.
class TestResultScreen extends StatefulWidget {
  const TestResultScreen({this.testId, this.resultData, super.key});

  final String? testId;
  final TestCardData? resultData;

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final TestCardData _result;

  String _solutionFilter = 'All'; // 'All' | 'Incorrect' | 'Unattempted'
  final Set<int> _expandedSolutions = {};
  bool _pdfBusy = false;

  // AI Coach (cache-first) state
  bool _coachLoadStarted = false;
  bool _coachLoading = false;
  bool _coachGenerating = false;
  bool _coachCached = false;
  String? _coachAttemptId;
  CoachDiagnostic? _diagnostic;
  String? _coachError;

  late List<ExamSolutionItem> _solutions;

  CoachReportRepository get _coachRepo => const SupabaseCoachReportRepository();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
      if (_tabController.index == 1) _loadCoachReport();
    });

    final tid = widget.testId ?? widget.resultData?.id ?? 'test_result_default';
    _result =
        widget.resultData ??
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

    _initializeSolutions();
  }

  void _initializeSolutions() {
    _solutions = const [
      ExamSolutionItem(
        questionNumber: 1,
        topic: 'Early Nationalist Movements',
        statement: 'Consider the following statements regarding the Ilbert Bill Controversy (1883):\n1. It sought to grant Indian magistrates the jurisdiction to try European British subjects.\n2. Lord Lytton was the Viceroy.\n3. Anglo-Indian opposition led to amendments.',
        options: [
          '1 and 2 only',
          '1 and 3 only',
          '2 and 3 only',
          '1, 2, and 3',
        ],
        correctIndex: 1,
        userIndex: 1, // Correct
        explanation: 'Statement 1 and 3 are correct. The Ilbert Bill was introduced during Lord Ripon\'s viceroyalty in 1883 (not Lord Lytton), aiming to eliminate judicial racial discrimination. Furious European opposition led to a compromise allowing European defendants to claim a trial by a jury comprising at least 50% Europeans.',
      ),
      ExamSolutionItem(
        questionNumber: 2,
        topic: 'Gandhian Era',
        statement: 'During the Indian National Movement, the "Champaran Satyagraha" (1917) was organized to protest against which system?',
        options: [
          'High land revenue rates imposed after drought',
          'The Tinkathia system forcing farmers to cultivate indigo on 3/20th of land',
          'The Rowlatt Act permitting detention without trial',
          'The imposition of salt tax in coastal Bihar',
        ],
        correctIndex: 1,
        userIndex: 1, // Correct
        explanation: 'The Champaran Satyagraha of 1917 was Mahatma Gandhi\'s first Satyagraha in India, launched against European planters who coerced peasants to grow indigo under the oppressive Tinkathia system.',
      ),
      ExamSolutionItem(
        questionNumber: 3,
        topic: 'Constitutional Developments',
        statement: 'With reference to the Cabinet Mission Plan of 1946, consider:\n1. It recommended a loose three-tier confederation.\n2. It unconditionally accepted the demand for Pakistan.\n3. It provided for an Interim Government.',
        options: ['1 and 3 only', '2 only', '1 and 2 only', '1, 2, and 3'],
        correctIndex: 0,
        userIndex: 3, // Incorrect
        explanation: 'The Cabinet Mission unequivocally rejected the demand for a sovereign Pakistan to maintain India\'s unity, but conceded provincial groupings. Hence statement 2 is incorrect.',
      ),
      ExamSolutionItem(
        questionNumber: 4,
        topic: 'Socio-Religious Reforms',
        statement: 'Who among the following founded the "Satyashodhak Samaj" in 1873 to liberate the Shudra and Untouchable castes?',
        options: [
          'Dr. B. R. Ambedkar',
          'Jyotirao Phule',
          'Sri Narayana Guru',
          'E. V. Ramasamy Naicker (Periyar)',
        ],
        correctIndex: 1,
        userIndex: -1, // Unattempted
        explanation: 'Jyotirao Phule founded the Satyashodhak Samaj (Truth-Seekers\' Society) in Pune on 24 September 1873 to fight caste injustice and promote education for girls and lower castes.',
      ),
      ExamSolutionItem(
        questionNumber: 5,
        topic: 'Civil Disobedience & Round Table',
        statement: 'The Gandhi-Irwin Pact signed in March 1931 included which of the following provisions?',
        options: [
          '1 and 2 only',
          '2 and 3 only',
          '1, 2, and 3',
          '1 and 3 only',
        ],
        correctIndex: 2,
        userIndex: 2, // Correct
        explanation: 'The pact endorsed release of non-violent political prisoners, right to peaceful picketing, and collection of salt for personal consumption without tax.',
      ),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onViewLeaderboard() {
    context.push('/tests/${_result.id}/leaderboard', extra: _result);
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
        data: _result,
        candidateName: _candidateName(),
        studentCode: ProfileService.currentProfile?.studentCode,
      );
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${_result.title} - scorecard.pdf',
      );
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not generate the scorecard PDF. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  String _coachErrorText(Object e) {
    if (e is AppError) return e.message;
    return 'Something went wrong while preparing your AI diagnostic. Please try again.';
  }

  Future<void> _loadCoachReport() async {
    if (_coachLoadStarted || _coachLoading) return;
    _coachLoadStarted = true;
    setState(() {
      _coachLoading = true;
      _coachError = null;
    });
    try {
      final attemptId = await _coachRepo.attemptIdForTest(_result.id);
      if (attemptId == null || attemptId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _coachAttemptId = null;
          _coachCached = true;
          _diagnostic = const CoachDiagnostic(
            summary: 'Strong conceptual retention in modern history, with minor precision drops on chronological ordering.',
            weakTopics: [
              'Government of India Act 1935',
              'Round Table Conferences Chronology',
            ],
            eliminationAdvice: [
              'When two statements appear mutually exclusive, verify dates prior to eliminating both.',
              'Review double negatives carefully on chronological timeline questions.',
            ],
            revisionPriorities: [
              'Review Gandhian era constitutional deadlocks.',
              'Solve 20 sectional MCQs on timeline questions.',
            ],
            coachMessage:
                'Focus on 50-50 elimination techniques for high precision.',
          );
        });
        return;
      }
      final cache = await _coachRepo.fetch(attemptId);
      if (!mounted) return;
      setState(() {
        _coachAttemptId = attemptId;
        _coachCached = cache.cached;
        _diagnostic = cache.report;
      });
    } catch (e) {
      // Released so the error card's retry can re-enter this method.
      _coachLoadStarted = false;
      if (!mounted) return;
      setState(() => _coachError = _coachErrorText(e));
    } finally {
      if (mounted) setState(() => _coachLoading = false);
    }
  }

  Future<void> _generateCoachReport() async {
    if (_coachGenerating) return;
    setState(() {
      _coachGenerating = true;
      _coachError = null;
    });
    try {
      final attemptId =
          _coachAttemptId ?? await _coachRepo.attemptIdForTest(_result.id);
      if (attemptId == null || attemptId.isEmpty) {
        throw const DataError(
          message: 'This attempt is not linked to a saved result yet. Re-take the test to unlock the AI diagnostic.',
        );
      }
      final cache = await _coachRepo.generateAndSave(attemptId);
      if (!mounted) return;
      setState(() {
        _coachAttemptId = attemptId;
        _coachCached = cache.cached;
        _diagnostic = cache.report;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _coachError = _coachErrorText(e));
    } finally {
      if (mounted) setState(() => _coachGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final score = _result.scoreObtained ?? 42.0;
    final totalMarks = _result.totalMarks;
    final accuracy = _result.accuracyPercentage ?? 84.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scorecard & Performance Analysis',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            key: const Key('share_scorecard_btn'),
            icon: _pdfBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
            tooltip: 'Share Scorecard',
            onPressed: _pdfBusy ? null : _onDownloadScorecard,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Hero Score Ring Card
                  _buildHeroScoreCard(
                    theme,
                    isDark,
                    score,
                    totalMarks,
                    accuracy,
                  ),
                  const SizedBox(height: 16),

                  // 2. 4 Quick Result Metric Cards
                  _buildMetricCardsRow(accuracy, isDark),
                  const SizedBox(height: 20),

                  // 3. Horizontal Segmented Bar (Correct, Incorrect, Unattempted)
                  _buildSegmentedDistributionBar(isDark),
                  const SizedBox(height: 20),

                  // 4. Topic Mastery Matrix (Strong vs Topics needing revision)
                  _buildTopicMasteryMatrix(isDark),
                  const SizedBox(height: 24),

                  // 5. Tabs: Solutions Review vs AI Coach
                  _buildSubTabBar(theme, isDark),
                  const SizedBox(height: 16),

                  // Subtab Content
                  if (_tabController.index == 0)
                    _buildSolutionsTab(isDark)
                  else
                    _buildAiCoachTab(isDark),

                  const SizedBox(height: 24),

                  // Bottom Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('view_cohort_leaderboard_btn'),
                          onPressed: _onViewLeaderboard,
                          icon: const Icon(
                            Icons.emoji_events_rounded,
                            size: 18,
                          ),
                          label: const Text('View Cohort Leaderboard 🏆'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Back to Tests'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroScoreCard(
    ThemeData theme,
    bool isDark,
    double score,
    double totalMarks,
    double accuracy,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFEFF6FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF3B82F6) : const Color(0xFFBFDBFE),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Radial / Circular Score ring
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: CircularProgressIndicator(
                      value: (score / totalMarks).clamp(0.0, 1.0),
                      strokeWidth: 8,
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        score.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        '/ ${totalMarks.toInt()}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 20),

              // Title, Rank and Celebratory pill
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _result.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.military_tech_rounded,
                          size: 16,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Rank #${_result.rank} of ${_result.totalParticipants} (Top 8%)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // +15 Study Points Added Celebratory Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🎖️', style: TextStyle(fontSize: 12)),
                          SizedBox(width: 4),
                          Text(
                            '+15 Study Points Added',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCardsRow(double accuracy, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: ResultMetricCard(
            label: 'Accuracy',
            value: '${accuracy.toStringAsFixed(1)}%',
            icon: Icons.track_changes_rounded,
            iconColor: const Color(0xFF10B981),
            badgeText: 'High Yield',
            badgeColor: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: ResultMetricCard(
            label: 'Time Spent',
            value: '28m 45s',
            icon: Icons.timer_outlined,
            iconColor: Color(0xFF0284C7),
            subtext: 'Pacing: 1.1m / Q',
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedDistributionBar(bool isDark) {
    const correct = 3;
    const incorrect = 1;
    const unattempted = 1;

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
          const Text(
            'ATTEMPT DISTRIBUTION & MARK BREAKDOWN',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),

          // Stacked horizontal segmented bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  Expanded(
                    flex: correct,
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                  Expanded(
                    flex: incorrect,
                    child: Container(color: const Color(0xFFEF4444)),
                  ),
                  Expanded(
                    flex: unattempted,
                    child: Container(
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Detail count chips (responsive Wrap)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _distributionChip(
                color: const Color(0xFF10B981),
                label: 'Correct',
                count: '$correct Qs (+6.0 M)',
              ),
              _distributionChip(
                color: const Color(0xFFEF4444),
                label: 'Incorrect',
                count: '$incorrect Qs (-0.66 M)',
              ),
              _distributionChip(
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                label: 'Skipped',
                count: '$unattempted Qs (0 M)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _distributionChip({
    required Color color,
    required String label,
    required String count,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
        Text(
          count,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTopicMasteryMatrix(bool isDark) {
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
          const Text(
            'TOPIC MASTERY MATRIX',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Strong topics
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF10B981),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Strong Topics (Accuracy > 75%)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _topicBadge(
                      'Early Nationalist Movements (100% • 1/1)',
                      true,
                    ),
                    const SizedBox(height: 4),
                    _topicBadge('Gandhian Era & Satyagraha (100% • 1/1)', true),
                    const SizedBox(height: 4),
                    _topicBadge(
                      'Civil Disobedience & Round Table (100% • 1/1)',
                      true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Topics needing revision
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4444),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Needs Revision (Accuracy < 50%)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _topicBadge(
                      'Constitutional Developments (0% • 0/1)',
                      false,
                    ),
                    const SizedBox(height: 4),
                    _topicBadge(
                      'Socio-Religious Reforms (Skipped • 0/1)',
                      false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topicBadge(String text, bool isStrong) {
    final color = isStrong ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSubTabBar(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: const [
          Tab(text: 'Full Solutions & Review'),
          Tab(text: '🤖 AI Performance Coach'),
        ],
      ),
    );
  }

  Widget _buildSolutionsTab(bool isDark) {
    final filters = ['All', 'Incorrect Only', 'Unattempted'];
    final filtered = _solutions.where((item) {
      if (_solutionFilter == 'Incorrect Only') return item.isIncorrect;
      if (_solutionFilter == 'Unattempted') return item.isUnattempted;
      return true;
    }).toList();

    return Column(
      children: [
        // Filter row
        Row(
          children: filters.map((f) {
            final isChosen = _solutionFilter == f;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f),
                selected: isChosen,
                onSelected: (selected) {
                  if (selected) setState(() => _solutionFilter = f);
                },
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        ...filtered.map((item) {
          final isExpanded = _expandedSolutions.contains(item.questionNumber);
          return _buildSolutionCard(item, isExpanded, isDark);
        }),
      ],
    );
  }

  Widget _buildSolutionCard(
    ExamSolutionItem item,
    bool isExpanded,
    bool isDark,
  ) {
    final Color badgeColor;
    final String statusText;
    if (item.isCorrect) {
      badgeColor = const Color(0xFF10B981);
      statusText = 'Correct (+2.0)';
    } else if (item.isIncorrect) {
      badgeColor = const Color(0xFFEF4444);
      statusText = 'Incorrect (-0.66)';
    } else {
      badgeColor = const Color(0xFF64748B);
      statusText = 'Unattempted (0.0)';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Question ${item.questionNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.statement,
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 10),

                // Option review list
                ...List.generate(item.options.length, (optIdx) {
                  final isCorrectOpt = optIdx == item.correctIndex;
                  final isUserPick = optIdx == item.userIndex;

                  Color optBg = Colors.transparent;
                  Color border = isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0);

                  if (isCorrectOpt) {
                    optBg = const Color(0xFF10B981).withValues(alpha: 0.12);
                    border = const Color(0xFF10B981);
                  } else if (isUserPick) {
                    optBg = const Color(0xFFEF4444).withValues(alpha: 0.12);
                    border = const Color(0xFFEF4444);
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: optBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${String.fromCharCode(65 + optIdx)}.',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.options[optIdx],
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        if (isCorrectOpt)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: Color(0xFF10B981),
                          ),
                        if (isUserPick && !isCorrectOpt)
                          const Icon(
                            Icons.cancel_rounded,
                            size: 16,
                            color: Color(0xFFEF4444),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          // Explanation Accordion Toggle
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedSolutions.remove(item.questionNumber);
                } else {
                  _expandedSolutions.add(item.questionNumber);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'In-Depth Academic Explanation',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: const Color(0xFF2563EB),
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded)
            Container(
              padding: const EdgeInsets.all(14),
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              child: Text(
                item.explanation,
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAiCoachTab(bool isDark) {
    final bodyColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final bodyTextStyle = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bodyColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI COHORT COACH DIAGNOSTIC REPORT',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              if (_coachCached && _diagnostic != null && !_diagnostic!.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'Cached Diagnostic Report',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 14),

          if (_coachLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Loading your diagnostic report…',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_coachError != null)
            _coachErrorCard(_coachError!, isDark)
          else if (_diagnostic != null && !_diagnostic!.isEmpty)
            ..._buildDiagnosticSections(_diagnostic!, bodyTextStyle, isDark)
          else
            _buildGenerateCta(isDark),
        ],
      ),
    );
  }

  Widget _coachErrorCard(String message, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF991B1B),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('coach_generate_retry'),
            onPressed: _coachGenerating
                ? null
                : () {
                    if (_coachAttemptId == null) {
                      _loadCoachReport();
                    } else {
                      _generateCoachReport();
                    }
                  },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDiagnosticSections(
    CoachDiagnostic diagnostic,
    TextStyle bodyTextStyle,
    bool isDark,
  ) {
    return [
      if (diagnostic.summary.isNotEmpty) ...[
        const Text(
          'Summary',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(diagnostic.summary, style: bodyTextStyle),
        const SizedBox(height: 16),
      ],
      if (diagnostic.eliminationAdvice.isNotEmpty) ...[
        const Text(
          '1. Elimination Strategy & Precision',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        ...diagnostic.eliminationAdvice.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $line', style: bodyTextStyle),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (diagnostic.weakTopics.isNotEmpty) ...[
        const Text(
          '2. Topics Needing Revision',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: diagnostic.weakTopics
              .map((topic) => _topicBadge(topic, false))
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
      if (diagnostic.revisionPriorities.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🎯 Action Plan for Next Mock:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: Color(0xFF065F46),
                ),
              ),
              const SizedBox(height: 6),
              ...diagnostic.revisionPriorities.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $line',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF065F46),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      if (diagnostic.coachMessage != null &&
          diagnostic.coachMessage!.trim().isNotEmpty &&
          diagnostic.coachMessage != diagnostic.summary) ...[
        const SizedBox(height: 16),
        Text(
          diagnostic.coachMessage!,
          style: TextStyle(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            height: 1.4,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ],
    ];
  }

  Widget _buildGenerateCta(bool isDark) {
    return Container(
      key: const Key('coach_generate_cta'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your AI diagnostic has not been generated yet.',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Generate a personalised breakdown of your weak topics, elimination strategy and revision priorities for this attempt. It is generated once and then cached on this device.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('generate_ai_diagnostic_btn'),
            onPressed: _coachGenerating ? null : _generateCoachReport,
            icon: _coachGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(
              _coachGenerating ? 'Generating…' : 'Generate AI Diagnostic',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
