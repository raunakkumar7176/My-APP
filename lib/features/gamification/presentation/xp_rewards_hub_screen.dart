import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/services/profile_service.dart';
import '../data/gamification_repository.dart';
import '../domain/leaderboard_entry.dart';

/// XP & Study Rewards Hub — opened by tapping the AppBar XP pill. Three
/// tabs: the real rulebook of what actually pays XP today, the Following
/// weekly leaderboard, and badges backed by real, honestly-computed data.
///
/// Deliberately does NOT show "+50 XP Earned!" for test completion the way
/// the original request described it — `rpc_submit_and_score_test` already
/// pays exactly +15 XP per attempt (`'test_completion'`), atomically and
/// exactly once; this hub reports that real number rather than a bigger,
/// unpaid one.
class XpRewardsHubScreen extends StatefulWidget {
  const XpRewardsHubScreen({super.key, this.repository = const GamificationRepository()});

  final GamificationRepository repository;

  @override
  State<XpRewardsHubScreen> createState() => _XpRewardsHubScreenState();
}

class _XpRewardsHubScreenState extends State<XpRewardsHubScreen> {
  @override
  Widget build(BuildContext context) {
    final totalXp = ProfileService.currentProfile?.totalPoints ?? 0;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('XP & Study Rewards'),
          bottom: const TabBar(tabs: [
            Tab(text: 'How to Earn'),
            Tab(text: 'Leaderboard'),
            Tab(text: 'Badges'),
          ]),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
              child: Column(
                children: [
                  Text(
                    '⚡ $totalXp Total XP',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Weekly XP resets every Monday 00:00',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _RulebookTab(),
                  _LeaderboardTab(repository: widget.repository),
                  _BadgesTab(repository: widget.repository),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RulebookTab extends StatelessWidget {
  const _RulebookTab();

  static const _rules = [
    ('📝', 'Complete a Test', '+15 XP', 'Awarded once per attempt, automatically.'),
    ('🎯', 'Practice a Drill', '+2 XP', 'Per correct answer, up to the daily practice cap.'),
    ('📅', 'Finish a Routine Session', '+20 XP', 'Once per completed session, per day.'),
    ('🔥', 'Keep a Daily Streak', '+10 XP', 'Claim once a day, based on real activity.'),
    ('👥', 'Invite a Friend', '+100 XP', 'When they sign up with your referral code.'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _rules.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final (emoji, title, amount, subtitle) = _rules[i];
        return Card(
          child: ListTile(
            leading: Text(emoji, style: const TextStyle(fontSize: 26)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle),
            trailing: Text(
              amount,
              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}

class _LeaderboardTab extends StatefulWidget {
  const _LeaderboardTab({required this.repository});

  final GamificationRepository repository;

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  bool _loading = true;
  String? _error;
  List<LeaderboardEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.repository.fetchFollowingWeeklyLeaderboard();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the leaderboard. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    // Only the caller in the list => following no one yet.
    if (_entries.length <= 1) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined,
                  size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              const Text(
                'Follow your friends to see who tops the study leaderboard this week!',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/community'),
                child: const Text('Find Peers'),
              ),
            ],
          ),
        ),
      );
    }

    final top3 = _entries.take(3).toList();
    final rest = _entries.skip(3).toList();
    final me = _entries.where((e) => e.isCurrentUser).cast<LeaderboardEntry?>().firstOrNull;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (top3.isNotEmpty) _Podium(entries: top3),
              const SizedBox(height: 12),
              for (final e in rest)
                Card(
                  color: e.isCurrentUser
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                      : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: e.avatarUrl != null ? NetworkImage(e.avatarUrl!) : null,
                      child: e.avatarUrl == null ? Text('#${e.rank}') : null,
                    ),
                    title: Text(e.fullName + (e.isCurrentUser ? ' (You)' : '')),
                    trailing: Text('${e.weeklyXp} XP', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
        if (me != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            color: Theme.of(context).colorScheme.primary,
            child: Text(
              'Your Rank: #${me.rank} • ${me.weeklyXp} XP',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<LeaderboardEntry> entries;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    // Render as 2nd, 1st, 3rd for the classic center-tallest podium look.
    final ordered = [
      if (entries.length > 1) entries[1],
      entries[0],
      if (entries.length > 2) entries[2],
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final e in ordered)
          Column(
            children: [
              Text(_medals[entries.indexOf(e)], style: const TextStyle(fontSize: 28)),
              CircleAvatar(
                radius: e == entries[0] ? 32 : 26,
                backgroundImage: e.avatarUrl != null ? NetworkImage(e.avatarUrl!) : null,
                child: e.avatarUrl == null
                    ? Text(e.fullName.isEmpty ? '?' : e.fullName.substring(0, 1))
                    : null,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 80,
                child: Text(
                  e.fullName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${e.weeklyXp} XP', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
      ],
    );
  }
}

class _Badge {
  const _Badge(this.emoji, this.title, this.description);
  final String emoji;
  final String title;
  final String description;
}

class _BadgesTab extends StatefulWidget {
  const _BadgesTab({required this.repository});

  final GamificationRepository repository;

  @override
  State<_BadgesTab> createState() => _BadgesTabState();
}

class _BadgesTabState extends State<_BadgesTab> {
  bool _loading = true;
  bool _hasAnyResult = false;
  bool _highAccuracy = false;
  int _streak = 0;
  int _weeklyRank = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.repository.hasAnyResult(),
      widget.repository.hasHighAccuracyResult(pct: 80),
      widget.repository.fetchCurrentStreak(),
      widget.repository.fetchFollowingWeeklyLeaderboard(),
    ]);
    if (!mounted) return;
    final leaderboard = results[3] as List<LeaderboardEntry>;
    final mine = leaderboard.where((e) => e.isCurrentUser).cast<LeaderboardEntry?>().firstOrNull;
    setState(() {
      _hasAnyResult = results[0] as bool;
      _highAccuracy = results[1] as bool;
      _streak = results[2] as int;
      _weeklyRank = mine?.rank ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final badges = <(_Badge, bool, String)>[
      (const _Badge('🎯', 'First Test Attempted', 'Complete your first test attempt.'), _hasAnyResult, _hasAnyResult ? 'Unlocked' : 'Not yet'),
      (const _Badge('🔥', '7-Day Consistency Warrior', 'Stay active 7 days in a row.'), _streak >= 7, '$_streak/7 days'),
      (const _Badge('⚡', 'Speed Demon', 'Score 80%+ accuracy in any test.'), _highAccuracy, _highAccuracy ? 'Unlocked' : 'Not yet'),
      (const _Badge('🏆', 'Top 3 Weekly Leader', 'Finish top 3 on the Following leaderboard.'), _weeklyRank >= 1 && _weeklyRank <= 3, _weeklyRank > 0 ? 'Rank #$_weeklyRank' : 'Not ranked yet'),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) {
        final (badge, unlocked, progress) = badges[i];
        return Card(
          child: InkWell(
            onTap: () => _showBadgeDetail(context, badge, unlocked, progress),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: unlocked ? 1 : 0.35,
                    child: Text(badge.emoji, style: const TextStyle(fontSize: 40)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    badge.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: unlocked ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(progress, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBadgeDetail(BuildContext context, _Badge badge, bool unlocked, String progress) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${badge.emoji} ${badge.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(badge.description),
            const SizedBox(height: 8),
            Text(unlocked ? 'Status: Unlocked ✅' : 'Progress: $progress'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}
