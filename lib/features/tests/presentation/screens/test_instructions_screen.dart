import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common/question_palette_grid.dart';
import '../widgets/common/test_card.dart';

/// Screen 3: Test Instructions & Readiness
/// High-contrast academic overview: Syllabus, Total Marks, Negative marking rules,
/// Server-timer notice, Question palette legend preview, and confirmation checkbox
/// unlocking [ Enter Examination Hall ➔ ].
class TestInstructionsScreen extends StatefulWidget {
  const TestInstructionsScreen({this.testId, this.testData, super.key});

  final String? testId;
  final TestCardData? testData;

  @override
  State<TestInstructionsScreen> createState() => _TestInstructionsScreenState();
}

class _TestInstructionsScreenState extends State<TestInstructionsScreen> {
  bool _confirmedReadiness = false;

  late final TestCardData _data;

  @override
  void initState() {
    super.initState();
    final tid =
        widget.testId ?? widget.testData?.id ?? 'test_default_instructions';
    _data =
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
          status: TestCardStatus.live,
        );
  }

  void _onEnterExamHall() {
    if (!_confirmedReadiness) return;
    context.push('/tests/${_data.id}/attempt', extra: _data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Examination Instructions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                  // Test Header Banner
                  _buildHeaderBanner(theme, isDark),
                  const SizedBox(height: 16),

                  // 2x2 Academic Parameters Grid
                  _buildParametersGrid(isDark),
                  const SizedBox(height: 20),

                  // Examination Syllabus & Pattern
                  _buildSyllabusSection(isDark),
                  const SizedBox(height: 20),

                  // Server-timer & Autosave Notice
                  _buildServerTimerNotice(isDark),
                  const SizedBox(height: 20),

                  // Question Palette Legend Preview
                  _buildPaletteLegendSection(isDark),
                  const SizedBox(height: 24),

                  // Readiness Confirmation Checkbox Card
                  _buildReadinessCard(theme, isDark),
                  const SizedBox(height: 24),

                  // Enter Examination Hall CTA
                  FilledButton.icon(
                    key: const Key('enter_examination_hall_btn'),
                    onPressed: _confirmedReadiness ? _onEnterExamHall : null,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text(
                      'Enter Examination Hall ➔',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      disabledBackgroundColor: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
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

  Widget _buildHeaderBanner(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _data.subject,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _data.difficulty.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _data.difficulty.color.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _data.difficulty.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _data.difficulty.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _data.mode,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _data.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParametersGrid(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _paramTile(
                icon: Icons.quiz_outlined,
                color: const Color(0xFF2563EB),
                label: 'Total Questions',
                value: '${_data.questionCount} Questions',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _paramTile(
                icon: Icons.timer_outlined,
                color: const Color(0xFF0284C7),
                label: 'Allotted Time',
                value: '${_data.durationMinutes} Minutes',
                isDark: isDark,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              _paramTile(
                icon: Icons.stars_rounded,
                color: const Color(0xFFD97706),
                label: 'Maximum Marks',
                value: '${_data.totalMarks.toInt()} Marks',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _paramTile(
                icon: Icons.error_outline_rounded,
                color: const Color(0xFFEF4444),
                label: 'Negative Marking',
                value: '-0.66 / Wrong',
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paramTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyllabusSection(bool isDark) {
    final rules = [
      'Each question carries 2.0 marks for a correct response.',
      'A negative penalty of 0.66 marks is deducted for every incorrect option.',
      'Zero marks are awarded or deducted for unattempted questions.',
      'You may mark questions for review and return to them anytime prior to final submission.',
      'All responses are recorded and synced continuously with the server.',
    ];

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
          const Row(
            children: [
              Icon(Icons.rule_rounded, color: Color(0xFF2563EB), size: 20),
              SizedBox(width: 8),
              Text(
                'EXAMINATION RULES & MARKING SCHEME',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...rules.map(
            (rule) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rule,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155),
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

  Widget _buildServerTimerNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF451A03).withValues(alpha: 0.5)
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded, color: Color(0xFFD97706), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Server Clock Synchronized: The countdown timer starts immediately upon entering the examination hall. The test will automatically conclude and submit when the timer reaches zero.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteLegendSection(bool isDark) {
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
          const Row(
            children: [
              Icon(Icons.grid_view_rounded, color: Color(0xFF8B5CF6), size: 20),
              SizedBox(width: 8),
              Text(
                'QUESTION PALETTE NAVIGATION GUIDE',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Render sample interactive grid
          QuestionPaletteGrid(
            totalQuestions: 8,
            currentIndex: 0,
            answeredIndices: const {1, 2},
            markedIndices: const {3},
            onQuestionSelected: (_) {},
            showLegend: true,
            crossAxisCount: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessCard(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: _confirmedReadiness
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : (isDark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _confirmedReadiness
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: _confirmedReadiness ? 1.8 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          key: const Key('confirm_readiness_checkbox'),
          value: _confirmedReadiness,
          onChanged: (val) =>
              setState(() => _confirmedReadiness = val ?? false),
          activeColor: const Color(0xFF2563EB),
          title: const Text(
            'I have read all instructions and confirm readiness',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(
            'I pledge to adhere to academic integrity and understand that the timer cannot be paused once started.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}
