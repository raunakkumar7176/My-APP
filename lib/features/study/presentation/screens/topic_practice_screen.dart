import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../test/widgets/question_source_step.dart';
import '../../domain/study_question.dart';
import '../controllers/topic_practice_controller.dart';

/// Screen 6: Topic Practice / Question Practice Screen.
///
/// Provides a focused, question-by-question academic learning environment where
/// students test concepts, check answers with immediate feedback, view rich
/// explanations, and review mistakes without test-taking pressure.
class TopicPracticeScreen extends StatefulWidget {
  const TopicPracticeScreen({
    super.key,
    required this.topicId,
    this.chapterId,
    this.topicTitle,
    this.chapterTitle,
    this.subjectTitle,
    this.subjectId,
    this.controller,
  });

  final String topicId;
  final String? chapterId;
  final String? topicTitle;
  final String? chapterTitle;
  final String? subjectTitle;
  final String? subjectId;
  final TopicPracticeController? controller;

  @override
  State<TopicPracticeScreen> createState() => _TopicPracticeScreenState();
}

class _TopicPracticeScreenState extends State<TopicPracticeScreen> {
  late final TopicPracticeController _controller;
  bool _isControllerOwned = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      if (_controller.questions.isEmpty &&
          !_controller.isLoading &&
          _controller.errorMessage == null) {
        _controller.loadQuestions();
      }
    } else {
      _isControllerOwned = true;
      _controller = TopicPracticeController(
        topicId: widget.topicId,
        chapterId: widget.chapterId,
        topicTitle: widget.topicTitle,
        chapterTitle: widget.chapterTitle,
        subjectTitle: widget.subjectTitle,
        subjectId: widget.subjectId,
      );
      _controller.loadQuestions();
    }
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    if (_isControllerOwned) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  Future<bool> _handleExitConfirmation() async {
    if (!_controller.hasUnsavedProgress) {
      return true;
    }

    final isHindi = _controller.isHindi;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isHindi ? 'अभ्यास सत्र छोड़ें?' : 'Exit Practice Session?',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          isHindi
              ? 'इस सत्र में आपकी वर्तमान प्रगति सहेजी नहीं जाएगी। क्या आप वाकई बाहर निकलना चाहते हैं?'
              : 'Your current progress in this practice session will not be saved. Are you sure you want to exit?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isHindi ? 'जारी रखें' : 'Keep Practicing'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isHindi ? 'बाहर निकलें' : 'Exit'),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isHindi = _controller.isHindi;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return PopScope(
      canPop: !_controller.hasUnsavedProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleExitConfirmation();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: _buildAppBar(context, isDark, isHindi),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _buildBody(context, isDark, isHindi),
            ),
          ),
        ),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isDark,
    bool isHindi,
  ) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final breadcrumbs = _buildBreadcrumbsText(isHindi);

    return AppBar(
      backgroundColor: cardBg,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final canExit = await _handleExitConfirmation();
              if (canExit && context.mounted) {
                Navigator.of(context).maybePop();
              }
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: textPrimary,
              ),
            ),
          ),
        ),
      ),
      titleSpacing: 10,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Topic Practice Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x332563EB)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x663B82F6)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.quiz_outlined,
                      size: 11,
                      color: isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isHindi ? 'विषय अभ्यास' : 'Topic Practice',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Counter chip
              if (!_controller.isLoading &&
                  _controller.questions.isNotEmpty &&
                  !_controller.isCompleted)
                Text(
                  isHindi
                      ? 'प्रश्न ${_controller.currentIndex + 1}/${_controller.totalQuestions}'
                      : 'Question ${_controller.currentIndex + 1}/${_controller.totalQuestions}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            breadcrumbs,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: textMuted,
            ),
          ),
        ],
      ),
      actions: [
        // Language Toggle Pill
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _controller.toggleLanguage(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate_rounded, size: 14, color: textPrimary),
                  const SizedBox(width: 5),
                  Text(
                    isHindi ? 'हिंदी' : 'EN',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _buildBreadcrumbsText(bool isHindi) {
    final sub = widget.subjectTitle ?? (isHindi ? 'विषय' : 'Subject');
    final chap = widget.chapterTitle ?? (isHindi ? 'अध्याय' : 'Chapter');
    final top = widget.topicTitle ?? (isHindi ? 'विषय' : 'Topic');
    return '$sub • $chap • $top';
  }

  // ── Body Dispatcher ───────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, bool isDark, bool isHindi) {
    if (_controller.isLoading && _controller.questions.isEmpty) {
      return _buildSkeletonLoader(isDark);
    }

    if (_controller.errorMessage != null && _controller.questions.isEmpty) {
      return _buildErrorState(isDark, isHindi);
    }

    if (_controller.questions.isEmpty) {
      return _buildEmptyState(isDark, isHindi);
    }

    if (_controller.isCompleted) {
      return _buildSessionSummary(context, isDark, isHindi);
    }

    return _buildActivePractice(context, isDark, isHindi);
  }

  // ── Active Practice View ──────────────────────────────────────────────────

  Widget _buildActivePractice(BuildContext context, bool isDark, bool isHindi) {
    final question = _controller.currentQuestion!;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 1. Session Progress Strip
        _buildProgressStrip(isDark, isHindi),
        const SizedBox(height: 16),

        // 2. Question Card
        Container(
          padding: const EdgeInsets.all(20),
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
              // Question Header Row: Q# pill and Difficulty Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0x332563EB)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? const Color(0x663B82F6)
                            : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Text(
                      'Q${_controller.currentIndex + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  _buildDifficultyPill(question.difficulty, isDark, isHindi),
                ],
              ),
              const SizedBox(height: 14),

              // Question Text (Multi-line, selectable)
              SelectionArea(
                child: Text(
                  question.question,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 3. Touch-Friendly Option Cards
        ...question.options.asMap().entries.map((entry) {
          final index = entry.key;
          final optionText = entry.value;
          return _buildOptionTile(
            index: index,
            optionText: optionText,
            question: question,
            isDark: isDark,
            isHindi: isHindi,
          );
        }),
        const SizedBox(height: 18),

        // 4. Action & Feedback Area
        _buildActionAndFeedbackArea(context, question, isDark, isHindi),
      ],
    );
  }

  // ── Session Progress Strip ────────────────────────────────────────────────

  Widget _buildProgressStrip(bool isDark, bool isHindi) {
    final total = _controller.totalQuestions;
    final answered = _controller.totalAnswered;
    final progress = total > 0 ? (answered / total).clamp(0.0, 1.0) : 0.0;

    final progressTrackBg = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final progressFillColor = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: progressTrackBg,
              valueColor: AlwaysStoppedAnimation<Color>(progressFillColor),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Micro Metric Badges
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // Correct Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x2610B981)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x4D10B981)
                          : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 13,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isHindi
                            ? '✓ ${_controller.correctCount} सही'
                            : '✓ ${_controller.correctCount} Correct',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Incorrect Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x26EF4444)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x4DEF4444)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.highlight_off,
                        size: 13,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isHindi
                            ? '✗ ${_controller.incorrectCount} गलत'
                            : '✗ ${_controller.incorrectCount} Incorrect',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Review Mode Indicator or Elapsed Time
            if (_controller.isReviewMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x26F59E0B)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.refresh_rounded,
                      size: 12,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isHindi ? 'गलती सुधार' : 'Mistake Review',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                '⏱️ ${_controller.formattedDuration}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Difficulty Pill ───────────────────────────────────────────────────────

  Widget _buildDifficultyPill(String difficulty, bool isDark, bool isHindi) {
    Color bg;
    Color border;
    Color text;
    String label;

    switch (difficulty.toLowerCase()) {
      case 'easy':
        bg = isDark ? const Color(0x2610B981) : const Color(0xFFECFDF5);
        border = isDark ? const Color(0x4D10B981) : const Color(0xFFA7F3D0);
        text = const Color(0xFF10B981);
        label = isHindi ? 'सरल' : 'Easy';
        break;
      case 'hard':
        bg = isDark ? const Color(0x26EF4444) : const Color(0xFFFEF2F2);
        border = isDark ? const Color(0x4DEF4444) : const Color(0xFFFECACA);
        text = const Color(0xFFEF4444);
        label = isHindi ? 'कठिन' : 'Hard';
        break;
      case 'medium':
      default:
        bg = isDark ? const Color(0x26F59E0B) : const Color(0xFFFEF3C7);
        border = isDark ? const Color(0x4DF59E0B) : const Color(0xFFFDE68A);
        text = const Color(0xFFD97706);
        label = isHindi ? 'मध्यम' : 'Medium';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  // ── Option Tile ───────────────────────────────────────────────────────────

  Widget _buildOptionTile({
    required int index,
    required String optionText,
    required StudyQuestion question,
    required bool isDark,
    required bool isHindi,
  }) {
    final isSelected = _controller.selectedOptionIndex == index;
    final isChecked = _controller.isAnswerChecked;
    final isCorrectOption = index == question.correctOption;
    final isChosenWrong = isChecked && isSelected && !isCorrectOption;

    // Design Tokens according to state
    Color surfaceColor;
    Color borderColor;
    Color textColor;
    Color badgeBg;
    Color badgeText;
    Widget? trailingIcon;

    if (!isChecked) {
      if (isSelected) {
        // Selected (Unchecked)
        surfaceColor = isDark
            ? const Color(0x332563EB)
            : const Color(0xFFEFF6FF);
        borderColor = isDark
            ? const Color(0xFF3B82F6)
            : const Color(0xFF93C5FD);
        textColor = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF);
        badgeBg = const Color(0xFF2563EB);
        badgeText = Colors.white;
        trailingIcon = const Icon(
          Icons.radio_button_checked,
          size: 19,
          color: Color(0xFF2563EB),
        );
      } else {
        // Default Neutral Option
        surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
        borderColor = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0);
        textColor = isDark ? Colors.white : const Color(0xFF0F172A);
        badgeBg = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
        badgeText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
        trailingIcon = Icon(
          Icons.radio_button_unchecked,
          size: 19,
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
        );
      }
    } else {
      // Answer Checked State
      if (isCorrectOption) {
        // Correct Option (either chosen or revealed)
        surfaceColor = isDark
            ? const Color(0x3310B981)
            : const Color(0xFFECFDF5);
        borderColor = isDark
            ? const Color(0xFF059669)
            : const Color(0xFFA7F3D0);
        textColor = isDark ? const Color(0xFF34D399) : const Color(0xFF065F46);
        badgeBg = const Color(0xFF10B981);
        badgeText = Colors.white;
        trailingIcon = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isHindi ? '✓ सही उत्तर' : '✓ Correct',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: Color(0xFF10B981),
            ),
          ],
        );
      } else if (isChosenWrong) {
        // Chosen Wrong Option
        surfaceColor = isDark
            ? const Color(0x33EF4444)
            : const Color(0xFFFEF2F2);
        borderColor = isDark
            ? const Color(0xFFDC2626)
            : const Color(0xFFFECACA);
        textColor = isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B);
        badgeBg = const Color(0xFFEF4444);
        badgeText = Colors.white;
        trailingIcon = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isHindi ? '✗ आपकी पसंद' : '✗ Your Choice',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.cancel_rounded,
              size: 20,
              color: Color(0xFFEF4444),
            ),
          ],
        );
      } else {
        // Unselected other neutral options
        surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
        borderColor = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0);
        textColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
        badgeBg = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
        badgeText = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
        trailingIcon = null;
      }
    }

    final optionLetter = String.fromCharCode(65 + index); // A, B, C, D

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isChecked ? null : () => _controller.selectOption(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                if (!isChecked && isSelected)
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                // Option Letter Badge (A, B, C, D)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    optionLetter,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: badgeText,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Option Content Text
                Expanded(
                  child: Text(
                    optionText,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: textColor,
                      height: 1.35,
                    ),
                  ),
                ),

                // Trailing Indicator / Icon
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  trailingIcon,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Action & Feedback Area ────────────────────────────────────────────────

  Widget _buildActionAndFeedbackArea(
    BuildContext context,
    StudyQuestion question,
    bool isDark,
    bool isHindi,
  ) {
    if (!_controller.isAnswerChecked) {
      // State A: Before Submit
      final canCheck = _controller.selectedOptionIndex != null;

      return AppButton.primary(
        label: isHindi ? 'उत्तर जांचें' : 'Check Answer',
        icon: Icons.check_circle_outline,
        onPressed: canCheck ? () => _controller.checkAnswer() : null,
      );
    }

    // State B: After Submit — Learning State
    final isCorrect = _controller.isCurrentAnswerCorrect;
    final isLast = _controller.isLastQuestion;

    final bannerBg = isCorrect
        ? (isDark ? const Color(0x3310B981) : const Color(0xFFECFDF5))
        : (isDark ? const Color(0x33EF4444) : const Color(0xFFFEF2F2));
    final bannerBorder = isCorrect
        ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
        : (isDark ? const Color(0xFFDC2626) : const Color(0xFFFECACA));
    final bannerTitleColor = isCorrect
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

    final explanationText = question.explanation.trim().isNotEmpty
        ? question.explanation
        : (isHindi
              ? 'इस प्रश्न के लिए कोई विस्तृत व्याख्या उपलब्ध नहीं है।'
              : 'No explanation available for this question.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Result Callout Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: bannerBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Icon(
                    isCorrect
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 22,
                    color: bannerTitleColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isCorrect
                          ? (isHindi
                                ? '✓ शाबाश! आपका उत्तर सही है।'
                                : '✓ Correct! Well done.')
                          : (isHindi
                                ? 'पुनरावलोकन आवश्यक • इस अवधारणा को समझें'
                                : 'Needs Review • Learn from this'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: bannerTitleColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Explanation Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 15,
                          color: isDark
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isHindi
                              ? 'व्याख्या एवं अवधारणा'
                              : 'EXPLANATION & CONCEPT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDark
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectionArea(
                      child: Text(
                        explanationText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Review Topic Theory link
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: Text(
                    isHindi
                        ? '📖 विषय की थ्योरी दोबारा पढ़ें'
                        : '📖 Review Topic Theory',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    // Navigate or pop back to topic theory reader
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.push('/study/topic/${widget.topicId}');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Primary CTA Button
        AppButton.primary(
          label: isLast
              ? (isHindi ? 'अभ्यास पूरा करें 🎉' : 'Finish Practice 🎉')
              : (isHindi ? 'अगला प्रश्न →' : 'Next Question →'),
          icon: isLast ? Icons.celebration : Icons.arrow_forward_rounded,
          onPressed: () => _controller.nextQuestion(),
        ),
      ],
    );
  }

  // ── Session Summary Screen ────────────────────────────────────────────────

  Widget _buildSessionSummary(BuildContext context, bool isDark, bool isHindi) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final total = _controller.totalQuestions;
    final correct = _controller.correctCount;
    final incorrect = _controller.incorrectCount;
    final accuracy = _controller.accuracyPercentage;
    final mistakeCount = _controller.mistakeCount;

    String motivationalMessage;
    if (accuracy == 100) {
      motivationalMessage = isHindi
          ? 'उत्कृष्ट प्रदर्शन! आपने इस विषय के सभी प्रश्नों के सही उत्तर दिए हैं।'
          : 'Flawless performance! You have fully mastered this topic concept.';
    } else if (accuracy >= 70) {
      motivationalMessage = isHindi
          ? 'शानदार प्रयास! अपनी गलतियों को दोहराकर अवधारणा को और मजबूत करें।'
          : 'Great effort! Review your mistakes below to lock in the key concepts.';
    } else {
      motivationalMessage = isHindi
          ? 'अच्छा अभ्यास! थ्योरी को दोबारा पढ़ें और गलतियों का पुनरावलोकन करें।'
          : 'Good practice run. Review the explanations to build strong understanding.';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      children: [
        // Trophy Icon & Congratulations Header
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0x332563EB) : const Color(0xFFEFF6FF),
              border: Border.all(
                color: isDark
                    ? const Color(0x663B82F6)
                    : const Color(0xFFBFDBFE),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: Text('🏆', style: TextStyle(fontSize: 40)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        Center(
          child: Text(
            isHindi ? 'अभ्यास पूर्ण हुआ!' : 'Practice Complete',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              motivationalMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Metrics Matrix (2x2 Grid)
        Container(
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
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: isHindi ? 'कुल प्रश्न' : 'Total Questions',
                      value: '$total',
                      color: textPrimary,
                      icon: Icons.quiz_outlined,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      label: isHindi ? 'सटीकता' : 'Accuracy',
                      value: '$accuracy%',
                      color: const Color(0xFF2563EB),
                      icon: Icons.track_changes_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: isHindi ? 'सही उत्तर' : 'Correct Answers',
                      value: '$correct',
                      color: const Color(0xFF10B981),
                      icon: Icons.check_circle_outline,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      label: isHindi ? 'गलत उत्तर' : 'Incorrect Answers',
                      value: '$incorrect',
                      color: const Color(0xFFEF4444),
                      icon: Icons.highlight_off,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Real Elapsed Time Chip
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  isHindi
                      ? 'सत्र अवधि: ${_controller.formattedDuration}'
                      : 'Session Time: ${_controller.formattedDuration}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Action Pathways
        // 1. Review Mistakes (if any)
        if (mistakeCount > 0) ...[
          AppButton.secondary(
            label: isHindi
                ? 'गलतियों का पुनरावलोकन करें ($mistakeCount) 🔄'
                : 'Review Mistakes ($mistakeCount) 🔄',
            icon: Icons.refresh_rounded,
            onPressed: () => _controller.startReviewMistakes(),
          ),
          const SizedBox(height: 12),
        ],

        // 2. Practice Again
        AppButton.outlined(
          label: isHindi ? 'पुनः अभ्यास करें 🔁' : 'Practice Again 🔁',
          icon: Icons.replay_rounded,
          onPressed: () => _controller.restartPractice(),
        ),
        const SizedBox(height: 12),

        // 3. Back to Topic
        AppButton.outlined(
          label: isHindi ? 'विषय पर वापस जाएं 📚' : 'Back to Topic 📚',
          icon: Icons.auto_stories_rounded,
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.push('/study/topic/${widget.topicId}');
            }
          },
        ),
        const SizedBox(height: 12),

        // 4. Take Chapter Test
        AppButton.primary(
          label: isHindi ? 'अध्याय टेस्ट दें 📝' : 'Take Chapter Test 📝',
          icon: Icons.assignment_turned_in_outlined,
          onPressed: () {
            final extraData = {
              'prefillSubjectId': widget.subjectId ?? '',
              'prefillChapterId': widget.chapterId ?? '',
              'prefillTopicId': widget.topicId,
              'prefillTitle':
                  '${widget.chapterTitle ?? "Chapter"} — Official Test',
              'initialSource': QuestionSource.books,
              'defaultMode': 'exam',
            };

            context.push(
              '/tests/create?source=books&chapterId=${widget.chapterId}',
              extra: extraData,
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    final tileBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Skeleton Loader ───────────────────────────────────────────────────────

  Widget _buildSkeletonLoader(bool isDark) {
    final shimmerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Progress placeholder
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: shimmerColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 20),

        // Question box skeleton
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: shimmerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 24,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 18,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 220,
                height: 18,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 4 Option skeletons
        for (int i = 0; i < 4; i++) ...[
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: shimmerColor),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),

        // Bottom CTA skeleton
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: shimmerColor,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark, bool isHindi) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x332563EB)
                    : const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.quiz_outlined,
                size: 36,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isHindi
                  ? 'इस विषय के लिए अभी कोई प्रश्न उपलब्ध नहीं हैं'
                  : 'No Practice Questions Available Yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isHindi
                  ? 'इस विषय के प्रश्न तैयार किए जा रहे हैं। आप संपूर्ण अध्याय के प्रश्नों का अभ्यास कर सकते हैं।'
                  : 'Practice questions are being curated for this specific topic. You can practice questions from the full chapter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            AppButton.primary(
              label: isHindi
                  ? 'पूरे अध्याय का अभ्यास करें'
                  : 'Practice Full Chapter',
              icon: Icons.auto_stories_rounded,
              onPressed: () {
                _controller.loadQuestions(forceChapterFallback: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Error State ───────────────────────────────────────────────────────────

  Widget _buildErrorState(bool isDark, bool isHindi) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 16),
            Text(
              isHindi ? 'लोड करने में समस्या आई' : 'Failed to Load Questions',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _controller.errorMessage ??
                  (isHindi
                      ? 'कृपया अपना इंटरनेट कनेक्शन जांचें और पुनः प्रयास करें।'
                      : 'Please check your connection and try again.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: textSecondary),
            ),
            const SizedBox(height: 20),
            AppButton.primary(
              label: isHindi ? 'पुनः प्रयास करें' : 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => _controller.loadQuestions(),
            ),
          ],
        ),
      ),
    );
  }
}
