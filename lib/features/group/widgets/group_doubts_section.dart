import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_doubt_summary.dart';
import '../state/group_hub_controller.dart';

/// Group Info's Doubts section: Open/Solved tabs with counts, keyset-
/// paginated, an optional "My doubts" filter, and a tap that jumps to the
/// message in chat (reusing [GroupHubController.jumpToMessage], already
/// built for this exact purpose — see its doc comment). All data/paging
/// state lives on the controller (0122); this widget only owns which tab
/// is selected, pure UI state.
class GroupDoubtsSection extends StatefulWidget {
  const GroupDoubtsSection({
    required this.controller,
    required this.onJumpToMessage,
    super.key,
  });

  final GroupHubController controller;

  /// Called with a doubt's message id after [GroupHubController
  /// .jumpToMessage] succeeds — the caller (chat screen or a pop back to
  /// it) decides how to actually scroll/highlight it.
  final void Function(String messageId) onJumpToMessage;

  @override
  State<GroupDoubtsSection> createState() => _GroupDoubtsSectionState();
}

class _GroupDoubtsSectionState extends State<GroupDoubtsSection> {
  bool _solvedTab = false;

  @override
  void initState() {
    super.initState();
    // Deferred to after this frame: calling a controller method that
    // notifyListeners()s synchronously (before its first await) from
    // inside initState fires while the ancestor (Group Info screen) is
    // still building its own children — "setState() called during
    // build". Every other section's load happens centrally in
    // GroupHubController.load() before the screen's first build; this
    // one is the first to lazy-load from within its own widget, so it's
    // the first to need this guard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = widget.controller;
      if (c.openDoubts.isEmpty) c.loadDoubtsPage(solved: false);
      if (c.solvedDoubts.isEmpty) c.loadDoubtsPage(solved: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // This widget triggers its own async load (above) rather than relying
    // solely on the Group Info screen having already loaded it — so it
    // must listen for that load completing itself, not just assume an
    // ancestor's listener will rebuild it. Harmless to also rebuild when
    // an ancestor does.
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final list = _solvedTab ? c.solvedDoubts : c.openDoubts;
    final hasMore = c.hasMoreDoubts(_solvedTab);

    return Column(
      key: const Key('group_doubts_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Doubts', style: theme.textTheme.titleMedium),
            const Spacer(),
            FilterChip(
              key: const Key('doubts_mine_only_chip'),
              label: const Text('My doubts'),
              selected: c.doubtsMineOnly,
              onSelected: (v) => c.setDoubtsMineOnly(v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _tabButton(
                key: const Key('doubts_tab_open'),
                label: 'Open',
                count: c.doubtCounts.open,
                selected: !_solvedTab,
                onTap: () => setState(() => _solvedTab = false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _tabButton(
                key: const Key('doubts_tab_solved'),
                label: 'Solved',
                count: c.doubtCounts.solved,
                selected: _solvedTab,
                onTap: () => setState(() => _solvedTab = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (c.doubtsLoading && list.isEmpty && c.doubtsError == null)
          const LinearProgressIndicator(key: Key('doubts_loading'))
        else if (c.doubtsError != null && list.isEmpty)
          Row(
            key: const Key('doubts_error'),
            children: [
              Expanded(
                child: Text(
                  c.doubtsError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('doubts_retry'),
                onPressed: () => c.loadDoubtsPage(solved: _solvedTab, reset: true),
                child: const Text('Retry'),
              ),
            ],
          )
        else if (list.isEmpty)
          Text(
            _solvedTab ? 'No solved doubts yet.' : 'No open doubts yet.',
            key: const Key('doubts_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final d in list) _tile(context, d),
        if (!c.doubtsLoading && list.isNotEmpty && hasMore)
          Center(
            child: TextButton(
              key: const Key('doubts_load_more'),
              onPressed: () => c.loadDoubtsPage(solved: _solvedTab),
              child: const Text('Load more'),
            ),
          ),
        if (c.doubtsLoading && list.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tabButton({
    required Key key,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      key: key,
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Widget _tile(BuildContext context, GroupDoubtSummary d) {
    return ListTile(
      key: Key('doubt_${d.id}'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      leading: Icon(
        d.doubtSolved
            ? Icons.check_circle_rounded
            : Icons.help_outline_rounded,
        color: d.doubtSolved
            ? AppColors.success
            : const Color(0xFFB45309),
      ),
      title: Text(
        d.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${d.senderName} · ${_when(d.createdAt)} · '
        '${d.replyCount} ${d.replyCount == 1 ? 'reply' : 'replies'}',
      ),
      onTap: () async {
        final ok = await widget.controller.jumpToMessage(d.id);
        if (!context.mounted) return;
        if (ok) {
          widget.onJumpToMessage(d.id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open that message.')),
          );
        }
      },
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
