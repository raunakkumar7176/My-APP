import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/question_bank_item.dart';
import '../state/question_bank_controller.dart';

/// Screen for viewing details of a single question bank item.
///
/// SECURITY: Correct answer visibility is controlled server-side via RLS.
/// The UI only displays what the server returns - it never fabricates
/// or exposes answer data that wasn't provided.
class QuestionBankDetailScreen extends StatefulWidget {
  const QuestionBankDetailScreen({
    required this.questionId,
    this.controller,
    super.key,
  });

  final String questionId;
  final QuestionBankController? controller;

  @override
  State<QuestionBankDetailScreen> createState() =>
      _QuestionBankDetailScreenState();
}

class _QuestionBankDetailScreenState extends State<QuestionBankDetailScreen> {
  late final QuestionBankController _controller;
  late final bool _ownsController;
  QuestionBankItem? _item;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? QuestionBankController();
    _loadQuestion();
  }

  Future<void> _loadQuestion() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final item = await _controller.getById(widget.questionId);
      if (mounted) {
        setState(() {
          _item = item;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load question';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending_review':
        return AppColors.warning;
      case 'archived':
        return AppColors.textSecondaryLight;
      case 'needs_revision':
        return AppColors.error;
      default:
        return AppColors.textSecondaryLight;
    }
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.warning;
      case 'hard':
        return AppColors.error;
      default:
        return AppColors.textSecondaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Details'),
        actions: [
          if (_item != null) ...[
            PopupMenuButton<String>(
              onSelected: (value) => _handleAction(value),
              itemBuilder: (context) => [
                if (_item!.status != 'archived')
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive'),
                  ),
                if (_item!.status == 'archived')
                  const PopupMenuItem(
                    value: 'restore',
                    child: Text('Restore'),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadQuestion,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_item == null) {
      return const Center(
        child: Text('Question not found'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status and difficulty chips
          _buildChips(theme),
          const SizedBox(height: 16),

          // Question text
          _buildSection(
            theme,
            title: 'Question',
            child: Text(
              _item!.question,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Options
          _buildSection(
            theme,
            title: 'Options',
            child: _buildOptions(theme),
          ),

          // Explanation (if present)
          if (_item!.hasExplanation) ...[
            const SizedBox(height: 16),
            _buildSection(
              theme,
              title: 'Explanation',
              child: Text(
                _item!.explanation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],

          // Metadata
          const SizedBox(height: 16),
          _buildSection(
            theme,
            title: 'Metadata',
            child: _buildMetadata(theme),
          ),

          // Governance info
          const SizedBox(height: 16),
          _buildSection(
            theme,
            title: 'Governance',
            child: _buildGovernance(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildChips(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(_item!.status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _item!.status.replaceAll('_', ' '),
            style: theme.textTheme.labelMedium?.copyWith(
              color: _statusColor(_item!.status),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _difficultyColor(_item!.difficulty).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _item!.difficulty,
            style: theme.textTheme.labelMedium?.copyWith(
              color: _difficultyColor(_item!.difficulty),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(ThemeData theme, {required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _item!.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Option letter
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _item!.correctOption == i
                        ? AppColors.success.withValues(alpha: 0.1)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: _item!.correctOption == i
                        ? Border.all(color: AppColors.success)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      String.fromCharCode(65 + i), // A, B, C, D
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Option text
                Expanded(
                  child: Text(
                    _item!.options[i].text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _item!.correctOption == i
                          ? AppColors.success
                          : null,
                    ),
                  ),
                ),
                // Correct indicator
                if (_item!.correctOption == i)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 20,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMetadata(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_item!.subjectName.isNotEmpty)
          _MetadataRow(label: 'Subject', value: _item!.subjectName),
        if (_item!.chapter.isNotEmpty)
          _MetadataRow(label: 'Chapter', value: _item!.chapter),
        _MetadataRow(label: 'Language', value: _item!.language.toUpperCase()),
        _MetadataRow(label: 'Type', value: _item!.questionType.toUpperCase()),
        _MetadataRow(label: 'Source', value: _item!.source),
        _MetadataRow(label: 'Times Used', value: _item!.timesUsed.toString()),
      ],
    );
  }

  Widget _buildGovernance(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetadataRow(
          label: 'Created',
          value: _formatDateTime(_item!.createdAt),
        ),
        if (_item!.updatedAt != null)
          _MetadataRow(
            label: 'Updated',
            value: _formatDateTime(_item!.updatedAt!),
          ),
        if (_item!.reviewedAt != null)
          _MetadataRow(
            label: 'Reviewed',
            value: _formatDateTime(_item!.reviewedAt!),
          ),
        if (_item!.archivedAt != null)
          _MetadataRow(
            label: 'Archived',
            value: _formatDateTime(_item!.archivedAt!),
          ),
        if (_item!.duplicateKey != null)
          _MetadataRow(
            label: 'Duplicate Key',
            value: _item!.duplicateKey!,
            showCopy: true,
          ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _handleAction(String action) async {
    if (_item == null) return;

    switch (action) {
      case 'archive':
        await _controller.archiveQuestion(_item!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Question archived')),
          );
          Navigator.of(context).pop();
        }
        break;
      case 'restore':
        await _controller.restoreQuestion(_item!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Question restored')),
          );
          Navigator.of(context).pop();
        }
        break;
    }
  }
}

/// Row displaying a metadata label and value.
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    this.showCopy = false,
  });

  final String label;
  final String value;
  final bool showCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (showCopy)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                // Copy to clipboard
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
