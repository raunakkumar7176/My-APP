import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group.dart';
import '../domain/group_role.dart';
import '../state/group_list_controller.dart';
import '../widgets/group_avatar.dart';
import '../widgets/join_group_sheet.dart';

/// Group Hub entry: the groups the caller owns or belongs to.
/// Navigation carries ids only; the hub loads its own data.
class GroupListScreen extends StatefulWidget {
  const GroupListScreen({
    this.controller,
    this.openJoinSheet = false,
    super.key,
  });

  /// Opens the join-with-code sheet as soon as the screen is shown
  /// (the /groups/join route).
  final bool openJoinSheet;

  /// Injectable for tests; defaults to a Supabase-backed controller.
  final GroupListController? controller;

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  late final GroupListController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupListController();
    _c.addListener(_onChanged);
    _c.load();
    if (widget.openJoinSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _join();
      });
    }
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

  Future<void> _create() async {
    await context.push('/groups/create');
    if (mounted) await _c.refresh();
  }

  Future<void> _join() async {
    final opened = await JoinGroupSheet.show(context, controller: _c);
    if (!mounted) return;
    await _c.refresh();
    if (opened != null && mounted) context.push('/groups/$opened');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            key: const Key('join_group_action'),
            tooltip: 'Join with code',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: _c.isBusy ? null : _join,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_group_fab'),
        onPressed: _create,
        icon: const Icon(Icons.group_add),
        label: const Text('Create Group'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (!_c.hasLoaded && _c.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_c.error != null && _c.groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_c.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _c.refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _c.refresh,
      child: _c.groups.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.groups_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No groups yet',
                        key: const Key('groups_empty'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a group or join one with an invite code.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _c.groups.length,
              itemBuilder: (_, i) => _GroupCard(
                group: _c.groups[i],
                onOpen: () async {
                  await context.push('/groups/${_c.groups[i].id}');
                  if (mounted) await _c.refresh();
                },
              ),
            ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onOpen});

  final Group group;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final role = GroupRole.fromDb(group.userRole);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        key: Key('group_card_${group.id}'),
        onTap: onOpen,
        leading: GroupAvatar(name: group.name, logoUrl: group.logoUrl),
        title: Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'} · ${role.label}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
