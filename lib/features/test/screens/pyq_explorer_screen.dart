import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../data/pyq_repository.dart';
import '../domain/pyq_models.dart';

enum PyqMode { practice, test }

/// Catalog screen: pick an exam → year → (optional) shift, then choose
/// Practice Mode (untimed, instant reveal) or Test Mode (timed simulation,
/// answers withheld until submit — see 0087_pyq_catalog_and_engine.sql).
class PyqExplorerScreen extends StatefulWidget {
  const PyqExplorerScreen({super.key});

  @override
  State<PyqExplorerScreen> createState() => _PyqExplorerScreenState();
}

class _PyqExplorerScreenState extends State<PyqExplorerScreen> {
  final _repo = const SupabasePyqRepository();
  List<PyqCatalogEntry> _catalog = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final catalog = await _repo.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load PYQ catalog. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Previous Year Questions')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                AppSpacing.vGapMd,
                Text(_error!, textAlign: TextAlign.center),
                AppSpacing.vGapMd,
                AppButton.primary(label: 'Retry', onPressed: _load),
              ],
            ),
          ),
        ],
      );
    }
    if (_catalog.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 48,
                  color: AppColors.textSecondaryLight,
                ),
                AppSpacing.vGapMd,
                Text(
                  'No previous year papers available yet.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        for (final entry in _catalog)
          _ExamCard(entry: entry, onLaunch: _openLaunchSheet),
      ],
    );
  }

  Future<void> _openLaunchSheet(
    PyqCatalogEntry entry,
    int year,
    String? shift,
  ) async {
    final mode = await showModalBottomSheet<PyqMode>(
      context: context,
      builder: (ctx) => _ModeSheet(examName: entry.examName, year: year),
    );
    if (mode == null || !mounted) return;

    if (mode == PyqMode.practice) {
      context.push(
        '/pyq-explorer/practice',
        extra: {
          'examName': entry.examName,
          'examYear': year,
          'examShift': shift,
        },
      );
    } else {
      context.push(
        '/pyq-explorer/test',
        extra: {
          'examName': entry.examName,
          'examYear': year,
          'examShift': shift,
        },
      );
    }
  }
}

class _ExamCard extends StatefulWidget {
  const _ExamCard({required this.entry, required this.onLaunch});

  final PyqCatalogEntry entry;
  final void Function(PyqCatalogEntry entry, int year, String? shift) onLaunch;

  @override
  State<_ExamCard> createState() => _ExamCardState();
}

class _ExamCardState extends State<_ExamCard> {
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      variant: AppCardVariant.outlined,
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.examName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainerLight,
                  borderRadius: AppRadius.pillBorder,
                ),
                child: Text(
                  '${entry.totalQuestions} Qs',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final y in entry.years)
                ChoiceChip(
                  label: Text('$y'),
                  selected: _selectedYear == y,
                  onSelected: (on) =>
                      setState(() => _selectedYear = on ? y : null),
                ),
            ],
          ),
          if (_selectedYear != null) ...[
            AppSpacing.vGapSm,
            Align(
              alignment: Alignment.centerRight,
              child: AppButton.primary(
                label: 'Start',
                size: AppButtonSize.sm,
                icon: Icons.arrow_forward,
                onPressed: () => widget.onLaunch(entry, _selectedYear!, null),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.examName, required this.year});

  final String examName;
  final int year;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$examName $year',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            AppSpacing.vGapSm,
            ListTile(
              leading: const Icon(
                Icons.self_improvement_outlined,
                color: AppColors.success,
              ),
              title: const Text('Practice Mode'),
              subtitle: const Text(
                'Untimed. Instant answer & explanation after every question.',
              ),
              onTap: () => Navigator.of(context).pop(PyqMode.practice),
            ),
            ListTile(
              leading: const Icon(
                Icons.timer_outlined,
                color: AppColors.primaryLight,
              ),
              title: const Text('Test Simulation'),
              subtitle: const Text(
                'Timed exam, answers revealed only after you submit.',
              ),
              onTap: () => Navigator.of(context).pop(PyqMode.test),
            ),
          ],
        ),
      ),
    );
  }
}
