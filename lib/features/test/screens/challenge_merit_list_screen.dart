import 'package:flutter/material.dart';

import '../state/challenge_controller.dart';

/// "Official Cohort Merit List": ranked results for one Peer Challenge
/// session via `rpc_get_challenge_merit_list` (migration 0061) — rank,
/// candidate, score, accuracy, time taken. The client never re-ranks; the
/// order returned by the server is rendered as-is.
class ChallengeMeritListScreen extends StatefulWidget {
  const ChallengeMeritListScreen({
    required this.sessionId,
    this.controller,
    super.key,
  });

  final String sessionId;
  final ChallengeController? controller;

  @override
  State<ChallengeMeritListScreen> createState() =>
      _ChallengeMeritListScreenState();
}

class _ChallengeMeritListScreenState extends State<ChallengeMeritListScreen> {
  late final ChallengeController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? ChallengeController();
    _c.addListener(_onChanged);
    _load();
  }

  Future<void> _load() async {
    if (widget.controller == null) {
      await _c.loadSession(widget.sessionId);
    }
    await _c.loadMeritList();
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

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Official Cohort Merit List')),
      body: _c.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _c.error != null
              ? Center(child: Text(_c.error!))
              : _c.meritList.isEmpty
                  ? const Center(child: Text('No results yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _c.meritList.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _c.meritList[index];
                        return ListTile(
                          key: Key('merit_row_${row.rank}'),
                          leading: CircleAvatar(
                            backgroundColor: row.rank <= 3
                                ? theme.colorScheme.primaryContainer
                                : null,
                            child: Text('#${row.rank}'),
                          ),
                          title: Text(row.candidateName),
                          subtitle: Text(row.candidateCode ?? ''),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                row.score.toStringAsFixed(1),
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                '${row.accuracy.toStringAsFixed(1)}% · '
                                '${_formatTime(row.timeTakenSeconds)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
