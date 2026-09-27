import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/profile_connection.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_service.dart';
import 'widgets/profile_avatar.dart';

/// `/profile/:userId/connections?tab=followers|following` — the target
/// user's followers or following list, each row backed by the real
/// `rpc_get_followers`/`rpc_get_following` RPCs (migration 0065). Search is
/// a local, instant filter over the already-loaded list (name or student
/// code) — not a separate server query.
class UserConnectionsScreen extends StatefulWidget {
  const UserConnectionsScreen({
    required this.userId,
    this.userName,
    this.initialTab = 'followers',
    super.key,
  });

  final String userId;
  final String? userName;

  /// 'followers' or 'following'.
  final String initialTab;

  @override
  State<UserConnectionsScreen> createState() => _UserConnectionsScreenState();
}

class _UserConnectionsScreenState extends State<UserConnectionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  String _query = '';

  List<ProfileConnection>? _followers;
  List<ProfileConnection>? _following;
  String? _followersError;
  String? _followingError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == 'following' ? 1 : 0,
    );
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    try {
      final rows = await ProfileService.getFollowers(widget.userId);
      if (mounted) setState(() => _followers = rows);
    } on AppError catch (e) {
      if (mounted) setState(() => _followersError = e.message);
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final rows = await ProfileService.getFollowing(widget.userId);
      if (mounted) setState(() => _following = rows);
    } on AppError catch (e) {
      if (mounted) setState(() => _followingError = e.message);
    }
  }

  List<ProfileConnection> _filter(List<ProfileConnection> items) {
    if (_query.isEmpty) return items;
    return items.where((c) {
      final name = c.fullName.toLowerCase();
      final code = (c.studentCode ?? '').toLowerCase();
      return name.contains(_query) || code.contains(_query);
    }).toList();
  }

  void _toggleFollow(ProfileConnection c, List<ProfileConnection>? list, void Function(List<ProfileConnection>) apply) {
    if (list == null) return;
    final wasFollowing = c.isFollowing;
    final next = [
      for (final item in list)
        if (item.id == c.id) item.copyWith(isFollowing: !wasFollowing) else item,
    ];
    apply(next);
    ProfileService.toggleFollow(c.id, currentlyFollowing: wasFollowing).catchError((e) {
      // Revert on failure — never leave the button showing a state the
      // server didn't actually record.
      if (!mounted) return;
      apply([
        for (final item in next)
          if (item.id == c.id) item.copyWith(isFollowing: wasFollowing) else item,
      ]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AppError ? e.message : 'Could not update follow status.')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName ?? 'Connections'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Followers'), Tab(text: 'Following')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('connections_search_field'),
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search by name or student code (MP-xxxxx)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildList(
                  items: _followers,
                  error: _followersError,
                  onRetry: _loadFollowers,
                  emptyMessage: 'No followers yet.',
                  onApply: (next) => setState(() => _followers = next),
                  isFollowersTab: true,
                ),
                _buildList(
                  items: _following,
                  error: _followingError,
                  onRetry: _loadFollowing,
                  emptyMessage: 'Not following anyone yet.',
                  onApply: (next) => setState(() => _following = next),
                  isFollowersTab: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList({
    required List<ProfileConnection>? items,
    required String? error,
    required VoidCallback onRetry,
    required String emptyMessage,
    required void Function(List<ProfileConnection>) onApply,
    required bool isFollowersTab,
  }) {
    if (error != null && items == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _filter(items);
    if (filtered.isEmpty) {
      return Center(child: Text(_query.isEmpty ? emptyMessage : 'No matches for "$_query".'));
    }
    final myId = AuthService.currentUser?.id;
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final c = filtered[index];
        final isSelf = c.id == myId;
        return ListTile(
          key: Key('connection_row_${c.id}'),
          onTap: () => context.push('/profile/${c.id}'),
          leading: ProfileAvatar(
            initials: c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
            avatarUrl: c.avatarUrl,
            radius: 20,
          ),
          title: Text(c.fullName.isNotEmpty ? c.fullName : 'Student'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.examTargets.isNotEmpty) Text(c.examTargets.join(', ')),
              if (c.studentCode != null && c.studentCode!.isNotEmpty)
                Chip(
                  label: Text(c.studentCode!, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          isThreeLine: c.examTargets.isNotEmpty && (c.studentCode?.isNotEmpty ?? false),
          trailing: isSelf
              ? null
              : OutlinedButton(
                  key: Key('follow_toggle_${c.id}'),
                  onPressed: () => _toggleFollow(
                    c,
                    items,
                    onApply,
                  ),
                  child: Text(
                    c.isFollowing
                        ? 'Following'
                        : (isFollowersTab ? 'Follow Back' : 'Follow'),
                  ),
                ),
        );
      },
    );
  }
}
