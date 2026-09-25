import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/question_bank_item.dart';
import '../state/question_bank_controller.dart';
import '../widgets/question_bank_filter_sheet.dart';
import '../widgets/question_bank_item_card.dart';

/// Screen for browsing and searching the question bank.
///
/// Supports:
/// - Paginated server-side loading
/// - Search with debounce
/// - Filters (status, subject, difficulty, language, type)
/// - Bulk selection for test creation
/// - Empty/error/loading states
class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({
    this.controller,
    this.selectionMode = false,
    this.onSelectionConfirmed,
    super.key,
  });

  final QuestionBankController? controller;

  /// When true, the screen operates in selection mode for test creation.
  final bool selectionMode;

  /// Called when user confirms selection in selection mode.
  final ValueChanged<List<QuestionBankItem>>? onSelectionConfirmed;

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  late final QuestionBankController _controller;
  late final bool _ownsController;
  final _search = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? QuestionBankController();
    _controller.addListener(_onChanged);
    _scrollController.addListener(_onScroll);

    if (widget.selectionMode) {
      _controller.enterSelectionMode();
    }

    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _controller.loadMore();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _scrollController.removeListener(_onScroll);
    if (_ownsController) _controller.dispose();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuestionBankFilterSheet(
        currentFilter: _controller.filter,
        onApply: (filter) {
          _controller.setFilter(
            status: filter.status,
            subjectId: filter.subjectId,
            subjectName: filter.subjectName,
            chapter: filter.chapter,
            topicNodeId: filter.topicNodeId,
            difficulty: filter.difficulty,
            language: filter.language,
            questionType: filter.questionType,
            source: filter.source,
          );
        },
      ),
    );
  }

  void _viewDetail(QuestionBankItem item) {
    context.push('/question-bank/${item.id}');
  }

  void _confirmSelection() {
    final selected = _controller.getSelectedItems();
    widget.onSelectionConfirmed?.call(selected);
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActiveFilters = !_controller.filter.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _controller.selectionMode
              ? 'Select Questions (${_controller.selectedCount})'
              : 'Question Bank',
        ),
        actions: [
          if (_controller.selectionMode) ...[
            TextButton(
              onPressed: _controller.selectedCount > 0
                  ? () => _controller.selectAll()
                  : null,
              child: const Text('Select All'),
            ),
            TextButton(
              onPressed: _controller.selectedCount > 0
                  ? () => _controller.deselectAll()
                  : null,
              child: const Text('Deselect All'),
            ),
          ] else ...[
            IconButton(
              icon: Icon(
                hasActiveFilters ? Icons.filter_list_off : Icons.filter_list,
                color: hasActiveFilters ? AppColors.primaryLight : null,
              ),
              onPressed: _showFilterSheet,
              tooltip: 'Filters',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(theme),

          // Active filters chips
          if (hasActiveFilters) _buildActiveFilters(theme),

          // Content
          Expanded(child: _buildContent(theme)),
        ],
      ),
      // Selection mode FAB
      floatingActionButton: _controller.selectionMode
          ? FloatingActionButton.extended(
              onPressed: _controller.hasSelection ? _confirmSelection : null,
              icon: const Icon(Icons.check),
              label: Text(
                'Add ${_controller.selectedCount} Question${_controller.selectedCount == 1 ? '' : 's'}',
              ),
            )
          : null,
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        key: const Key('bank_search'),
        controller: _search,
        onChanged: (value) {
          // Debounce search - will be handled by controller
          _controller.search(value);
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search questions...',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _search.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _controller.search('');
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildActiveFilters(ThemeData theme) {
    final chips = <Widget>[];

    if (_controller.filter.status != null) {
      chips.add(
        Chip(
          label: Text('Status: ${_controller.filter.status}'),
          onDeleted: () => _controller.setFilter(status: null),
        ),
      );
    }
    if (_controller.filter.subjectName != null) {
      chips.add(
        Chip(
          label: Text('Subject: ${_controller.filter.subjectName}'),
          onDeleted: () => _controller.setFilter(subjectName: null),
        ),
      );
    }
    if (_controller.filter.difficulty != null) {
      chips.add(
        Chip(
          label: Text('Difficulty: ${_controller.filter.difficulty}'),
          onDeleted: () => _controller.setFilter(difficulty: null),
        ),
      );
    }
    if (_controller.filter.language != null) {
      chips.add(
        Chip(
          label: Text('Language: ${_controller.filter.language}'),
          onDeleted: () => _controller.setFilter(language: null),
        ),
      );
    }
    if (_controller.filter.questionType != null) {
      chips.add(
        Chip(
          label: Text('Type: ${_controller.filter.questionType}'),
          onDeleted: () => _controller.setFilter(questionType: null),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ...chips,
          if (chips.length > 1)
            ActionChip(
              label: const Text('Clear All'),
              onPressed: () => _controller.clearFilters(),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_controller.isLoading && _controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.error != null && _controller.items.isEmpty) {
      return _buildErrorState(theme);
    }

    if (_controller.items.isEmpty) {
      return _buildEmptyState(theme);
    }

    return _buildQuestionList(theme);
  }

  Widget _buildErrorState(ThemeData theme) {
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
              _controller.error ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _controller.load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final hasFilters = !_controller.filter.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters ? Icons.filter_list_off : Icons.menu_book_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No questions match your filters'
                  : 'No questions in the bank yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _controller.clearFilters(),
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionList(ThemeData theme) {
    return ListView.builder(
      key: const Key('bank_list'),
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _controller.items.length + (_controller.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _controller.items.length) {
          // Loading indicator for next page
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = _controller.items[index];
        return QuestionBankItemCard(
          key: ValueKey(item.id),
          item: item,
          isSelected: _controller.selectedIds.contains(item.id),
          selectionMode: _controller.selectionMode,
          onTap: () {
            if (_controller.selectionMode) {
              _controller.toggleSelection(item.id);
            } else {
              _viewDetail(item);
            }
          },
          onLongPress: () {
            if (!_controller.selectionMode) {
              _controller.enterSelectionMode();
              _controller.toggleSelection(item.id);
            }
          },
        );
      },
    );
  }
}
