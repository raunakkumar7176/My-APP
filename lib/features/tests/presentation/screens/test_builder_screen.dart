import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common/test_card.dart';

/// Screen 2: Progressive Test Builder
/// Features multi-section workspace (Mobile: Accordions | Desktop: 2-Column with live sticky preview card)
/// Sections:
/// A: Basic Info (Title, Subject, Chapter, Test Mode)
/// B: Question Source (My Study, Question Bank, AI Generator, Document)
/// C: Question Matrix (Count stepper, 3-tier Easy/Medium/Hard distribution bar)
/// D: Marking & Timer (Marks, Negative deduction, Duration slider)
/// Sticky Bottom Dock: Live calculation summary with [ Launch Test 🚀 ] CTA.
class TestBuilderScreen extends StatefulWidget {
  const TestBuilderScreen({super.key});

  @override
  State<TestBuilderScreen> createState() => _TestBuilderScreenState();
}

class _TestBuilderScreenState extends State<TestBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController(
    text: 'Modern Indian History: Comprehensive Prelims Mock',
  );
  final TextEditingController _chapterController = TextEditingController(
    text: 'Socio-Religious Movements & Revolt of 1857',
  );

  String _selectedSubject = 'History';
  String _selectedMode = 'Exam Simulation';
  String _selectedSource = 'question_bank';

  int _questionCount = 25;
  double _marksPerQuestion = 2.0;
  double _negativeMarks = 0.66;
  int _durationMinutes = 45;

  // Difficulty ratio percentages
  int _easyPercent = 30;
  int _mediumPercent = 50;
  int _hardPercent = 20;

  @override
  void dispose() {
    _titleController.dispose();
    _chapterController.dispose();
    super.dispose();
  }

  void _onLaunchTest() {
    if (_formKey.currentState?.validate() != true) return;

    final testData = TestCardData(
      id: 'custom_test_${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Custom Examination',
      subject: _selectedSubject,
      difficulty: _hardPercent >= 40
          ? TestCardDifficulty.hard
          : (_mediumPercent >= 40
                ? TestCardDifficulty.medium
                : TestCardDifficulty.easy),
      mode: _selectedMode,
      questionCount: _questionCount,
      totalMarks: _questionCount * _marksPerQuestion,
      durationMinutes: _durationMinutes,
      status: TestCardStatus.live,
    );

    context.push('/tests/${testData.id}/instructions', extra: testData);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Progressive Test Builder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTabletOrDesktop = constraints.maxWidth >= 720;

          if (isTabletOrDesktop) {
            // 2-Column Desktop / Tablet layout
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionA(theme, isDark),
                          const SizedBox(height: 20),
                          _buildSectionB(theme, isDark),
                          const SizedBox(height: 20),
                          _buildSectionC(theme, isDark),
                          const SizedBox(height: 20),
                          _buildSectionD(theme, isDark),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildDesktopLivePreview(theme, isDark),
                  ),
                ),
              ],
            );
          }

          // Mobile 1-Column layout with sticky bottom dock
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionA(theme, isDark),
                        const SizedBox(height: 16),
                        _buildSectionB(theme, isDark),
                        const SizedBox(height: 16),
                        _buildSectionC(theme, isDark),
                        const SizedBox(height: 16),
                        _buildSectionD(theme, isDark),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              _buildMobileStickyDock(theme, isDark),
            ],
          );
        },
      ),
    );
  }

  // ── Section A: Basic Info ──
  Widget _buildSectionA(ThemeData theme, bool isDark) {
    return _buildCardWrapper(
      title: 'SECTION A: BASIC INFORMATION',
      subtitle: 'Examination title, subject stream, and test mode',
      icon: Icons.edit_note_rounded,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Test Title *',
              hintText: 'e.g. Modern Indian History Mock 1',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Title is required' : null,
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 14),

          // Subject & Test Mode Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedSubject,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items:
                      [
                            'History',
                            'Polity',
                            'Geography',
                            'Science',
                            'Economy',
                            'CSAT',
                          ]
                          .map(
                            (sub) => DropdownMenuItem(
                              value: sub,
                              child: Text(sub, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedSubject = val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedMode,
                  decoration: InputDecoration(
                    labelText: 'Test Mode',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items:
                      [
                            'Exam Simulation',
                            'Practice Mode',
                            'Speed Drill',
                            'Cohort Test',
                          ]
                          .map(
                            (mode) => DropdownMenuItem(
                              value: mode,
                              child: Text(
                                mode,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedMode = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Chapter / Subtopic
          TextFormField(
            controller: _chapterController,
            decoration: InputDecoration(
              labelText: 'Focus Chapter or Topic',
              hintText: 'e.g. Constitutional Framework & Supreme Court',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),
        ],
      ),
    );
  }

  // ── Section B: Question Source ──
  Widget _buildSectionB(ThemeData theme, bool isDark) {
    final sources = [
      {
        'id': 'my_study',
        'title': '📚 My Study & Notes',
        'desc': 'Curated from your active chapters, notes and bookmarks',
      },
      {
        'id': 'question_bank',
        'title': '🏛️ Question Bank',
        'desc': 'Authentic previous year & high-yield model questions',
      },
      {
        'id': 'ai_generator',
        'title': '🤖 AI Generator',
        'desc': 'Dynamically generate fresh, exam-calibrated MCQs via AI',
      },
      {
        'id': 'document_pdf',
        'title': '📄 Document / PDF',
        'desc': 'Extract and format questions directly from notes or PDF',
      },
    ];

    return _buildCardWrapper(
      title: 'SECTION B: QUESTION SOURCE',
      subtitle: 'Select where test questions will be pulled from',
      icon: Icons.source_rounded,
      isDark: isDark,
      child: Column(
        children: sources.map((src) {
          final isSelected = _selectedSource == src['id'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedSource = src['id']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : (isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : (isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0)),
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            src['title']!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            src['desc']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section C: Question Matrix ──
  Widget _buildSectionC(ThemeData theme, bool isDark) {
    return _buildCardWrapper(
      title: 'SECTION C: QUESTION MATRIX',
      subtitle: 'Total volume and 3-tier difficulty distribution',
      icon: Icons.tune_rounded,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question count stepper
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question Count',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Total items in exam session',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    onPressed: _questionCount > 5
                        ? () => setState(() => _questionCount -= 5)
                        : null,
                    icon: const Icon(Icons.remove, size: 16),
                  ),
                  Container(
                    width: 50,
                    alignment: Alignment.center,
                    child: Text(
                      '$_questionCount',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _questionCount < 100
                        ? () => setState(() => _questionCount += 5)
                        : null,
                    icon: const Icon(Icons.add, size: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Quick Selection Chips for Count
          Wrap(
            spacing: 8,
            children: [10, 20, 25, 50, 100].map((count) {
              final isChosen = _questionCount == count;
              return ChoiceChip(
                label: Text('$count Qs'),
                selected: isChosen,
                onSelected: (selected) {
                  if (selected) setState(() => _questionCount = count);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // 3-Tier Distribution Bar Preview
          const Text(
            'Difficulty Weightage Ratio',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: _easyPercent,
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                  Expanded(
                    flex: _mediumPercent,
                    child: Container(color: const Color(0xFFF59E0B)),
                  ),
                  Expanded(
                    flex: _hardPercent,
                    child: Container(color: const Color(0xFFEF4444)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                '🟢 Easy: $_easyPercent%',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '🟡 Medium: $_mediumPercent%',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '🔴 Hard: $_hardPercent%',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Preset Distribution Chips
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Balanced (30/50/20)'),
                onPressed: () {
                  setState(() {
                    _easyPercent = 30;
                    _mediumPercent = 50;
                    _hardPercent = 20;
                  });
                },
              ),
              ActionChip(
                label: const Text('Foundational (50/40/10)'),
                onPressed: () {
                  setState(() {
                    _easyPercent = 50;
                    _mediumPercent = 40;
                    _hardPercent = 10;
                  });
                },
              ),
              ActionChip(
                label: const Text('Challenging (15/45/40)'),
                onPressed: () {
                  setState(() {
                    _easyPercent = 15;
                    _mediumPercent = 45;
                    _hardPercent = 40;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section D: Marking & Timer ──
  Widget _buildSectionD(ThemeData theme, bool isDark) {
    return _buildCardWrapper(
      title: 'SECTION D: MARKING & TIMER',
      subtitle: 'Marks calculation and strict examination duration',
      icon: Icons.timer_outlined,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '$_marksPerQuestion',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Marks / Correct (+)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (val) {
                    final p = double.tryParse(val);
                    if (p != null && p > 0) {
                      setState(() => _marksPerQuestion = p);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: '$_negativeMarks',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Negative Deduction (-)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (val) {
                    final p = double.tryParse(val);
                    if (p != null && p >= 0) setState(() => _negativeMarks = p);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Duration Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Allotted Duration',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
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
                  '$_durationMinutes Minutes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _durationMinutes.toDouble(),
            min: 15,
            max: 180,
            divisions: 33,
            label: '$_durationMinutes mins',
            onChanged: (val) => setState(() => _durationMinutes = val.toInt()),
          ),
        ],
      ),
    );
  }

  // ── Desktop Sticky Live Preview ──
  Widget _buildDesktopLivePreview(ThemeData theme, bool isDark) {
    final previewData = TestCardData(
      id: 'preview_test',
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Custom Examination',
      subject: _selectedSubject,
      difficulty: _hardPercent >= 40
          ? TestCardDifficulty.hard
          : (_mediumPercent >= 40
                ? TestCardDifficulty.medium
                : TestCardDifficulty.easy),
      mode: _selectedMode,
      questionCount: _questionCount,
      totalMarks: _questionCount * _marksPerQuestion,
      durationMinutes: _durationMinutes,
      status: TestCardStatus.live,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'LIVE TEST SPECIFICATION PREVIEW',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        TestCard(data: previewData),
        const SizedBox(height: 16),

        // Live calculation tile
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Calculated Blueprint',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                '$_questionCount Questions • ${(_questionCount * _marksPerQuestion).toInt()} Marks • $_durationMinutes Mins',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Negative Marking: -$_negativeMarks / wrong answer',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        FilledButton.icon(
          key: const Key('desktop_launch_test_btn'),
          onPressed: _onLaunchTest,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: const Text(
            'Launch Test 🚀',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ── Mobile Sticky Bottom Dock ──
  Widget _buildMobileStickyDock(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Summary',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  Text(
                    '$_questionCount Qs • ${(_questionCount * _marksPerQuestion).toInt()} M • ${_durationMinutes}m',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const Key('mobile_launch_test_btn'),
              onPressed: _onLaunchTest,
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: const Text('Launch Test 🚀'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardWrapper({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
