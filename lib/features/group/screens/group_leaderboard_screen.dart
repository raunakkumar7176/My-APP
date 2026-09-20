import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/test.dart';
import '../../test/domain/test_lifecycle.dart';
import '../domain/group_test_results.dart';
import '../state/group_leaderboard_controller.dart';

/// Group test leaderboard (G12, F-10 remediation). Shows the server ranking
/// returned by `rpc_get_leaderboard` for a single group test — no AI, no
/// client-side ranking, no `results` reads for other users.
///
/// Access: the server serves rows to the test creator, members of the test's
/// group and participants (remediated 2026-09-20). Non-members, removed members, anon, and
/// cross-group callers are denied by the server.
class GroupLeaderboardScreen extends StatefulWidget {
  const GroupLeaderboardScreen({
    required this.groupId,
    required this.testId,
    this.controller,
    super.key,
  });

  final String groupId;
  final String testId;
  final GroupLeaderboardController? controller;

  @override
  State<GroupLeaderboardScreen> createState() => _GroupLeaderboardScreenState();
}

class _GroupLeaderboardScreenState extends State<GroupLeaderboardScreen> {
  late final GroupLeaderboardController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        GroupLeaderboardController(groupId: widget.groupId, testId: widget.testId);
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

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leaderboard')),
        body: const Center(
          child: CircularProgressIndicator(key: Key('leaderboard_loading')),
        ),
      );
    }
    if (_c.accessDenied) {
      return _message(
        key: const Key('leaderboard_denied'),
        icon: Icons.lock_outline,
        title: 'Leaderboard not available',
        body: 'This test does not belong to a group you are a member of.',
      );
    }
    if (_c.test == null) {
      return _message(
        key: const Key('leaderboard_error'),
        icon: Icons.error_outline,
        title: 'Could not load leaderboard',
        body: _c.error ?? 'Please try again.',
        action: FilledButton(
          key: const Key('leaderboard_retry'),
          onPressed: _c.load,
          child: const Text('Retry'),
        ),
      );
    }
    final test = _c.test!;
    final theme = Theme.of(context);
    // F-10: ordinary members see only their own result; owners / analytics
    // holders see the full server-ranked leaderboard.
    final displayEntries = _c.canSeeFullLeaderboard
        ? _c.entries
        : [?_c.myEntry];
    return Scaffold(
      appBar: AppBar(title: Text('${test.title} · Leaderboard')),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: displayEntries.isEmpty
            ? ListView(
                key: const Key('leaderboard_empty_list'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.leaderboard_outlined,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No results yet',
                          key: const Key('leaderboard_empty'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          GroupResultsAccess.isResultsPhase(test.status)
                              ? 'Results have not been generated yet. A group manager must generate results first.'
                              : 'This test is not over yet; the leaderboard is available once results are generated.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                key: const Key('leaderboard_list'),
                padding: const EdgeInsets.all(16),
                itemCount: displayEntries.length + 1, // +1 for summary header
                itemBuilder: (context, index) {
                  if (index == 0) return _header(theme, test, _c.entries);
                  final e = displayEntries[index - 1];
                  return _entryTile(theme, e);
                },
              ),
      ),
    );
  }

  Widget _header(ThemeData theme, Test test, List<LeaderboardEntry> entries) {
    final my = _c.myEntry;
    final fullView = _c.canSeeFullLeaderboard;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${TestLifecycle.statusLabel(test.status)} · ${_c.group?.name ?? ''}',
            key: const Key('leaderboard_meta'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          if (fullView) ...[
            // Owner / analytics holder: full ranking with participant count
            // and per-entry leaderboard tiles (rendered by the parent list).
            Text(
              '${entries.length} ranked participant${entries.length == 1 ? '' : 's'}',
              key: const Key('leaderboard_count'),
              style: theme.textTheme.titleSmall,
            ),
            if (my != null) ...[
              const SizedBox(height: 4),
              Text(
                'Your rank: ${my.rank} · ${_num(my.score)} / ${_num(my.maxScore)}'
                '${my.percentage != null ? ' · ${_num(my.percentage)}%' : ''}',
                key: const Key('my_leaderboard_summary'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ] else ...[
            // Ordinary member: "Your result" only — no rank, no participant
            // count, no other users' entries (the server RPC already returns
            // only the caller's row for members).
            if (my != null)
              Text(
                'Your result: ${_num(my.score)} / ${_num(my.maxScore)}'
                '${my.percentage != null ? ' · ${_num(my.percentage)}%' : ''}',
                key: const Key('my_leaderboard_summary'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                'No result recorded for this test.',
                key: const Key('my_leaderboard_summary'),
                style: theme.textTheme.bodyMedium,
              ),
          ],
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }

  Widget _entryTile(ThemeData theme, LeaderboardEntry e) {
    final medal = switch (e.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return Card(
      key: Key('leaderboard_entry_${e.userId}'),
      color: e.isCurrentUser
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: SizedBox(
          width: 40,
          child: Center(
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 20))
                : CircleAvatar(
                    radius: 16,
                    child: Text(
                      '${e.rank}',
                      key: Key('rank_${e.userId}'),
                    ),
                  ),
          ),
        ),
        title: Text(
          e.label,
          key: Key('label_${e.userId}'),
          style: e.isCurrentUser
              ? const TextStyle(fontWeight: FontWeight.w600)
              : null,
        ),
        subtitle: Text(
          '${_num(e.score)} / ${_num(e.maxScore)}'
          '${e.percentage != null ? ' · ${_num(e.percentage)}%' : ''}'
          '${e.accuracy != null ? ' · Acc ${_num(e.accuracy)}%' : ''}',
          key: Key('score_${e.userId}'),
        ),
        trailing: Text(
          'C${e.correctCount ?? 0} W${e.wrongCount ?? 0} U${e.unansweredCount ?? 0}',
          key: Key('counts_${e.userId}'),
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  static String _num(double? v) {
    if (v == null) return '--';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  Widget _message({
    required Key key,
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: Center(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  FilledButton(
                    onPressed: () => context.go('/groups/${widget.groupId}/tests'),
                    child: const Text('Back to group tests'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
