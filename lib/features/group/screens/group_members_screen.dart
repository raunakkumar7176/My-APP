import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_role.dart';
import '../state/group_hub_controller.dart';
import '../widgets/member_tile.dart';

/// Members Hub: the permitted roster with local search, role filter, member
/// detail, and the permission-aware role / remove actions shared with the
/// Group Hub. Access is membership (the controller refuses non-members).
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({required this.groupId, this.controller, super.key});

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late final GroupHubController _c;
  late final bool _owns;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupHubController(groupId: widget.groupId);
    _c.addListener(_onChanged);
    _search.text = _c.memberQuery;
    if (!_c.hasLoaded) _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Members')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.accessDenied || (_c.group == null && _c.error == null)) {
      return _message(
        'Group not available',
        'This group does not exist, or you are not a member of it.',
      );
    }
    if (_c.group == null || (_c.error != null && _c.members.isEmpty)) {
      return _message(
        'Could not load members',
        _c.error ?? 'Please try again.',
        action: FilledButton(
          key: const Key('members_retry'),
          onPressed: _c.load,
          child: const Text('Retry'),
        ),
      );
    }

    final group = _c.group!;
    final members = _c.filteredMembers;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Members · ${_c.memberCount}',
          key: const Key('members_title'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const Key('member_search'),
              controller: _search,
              onChanged: _c.setMemberQuery,
              decoration: InputDecoration(
                hintText: 'Search by name or student code',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _c.memberQuery.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('member_search_clear'),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _c.setMemberQuery('');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: const Key('role_chip_all'),
                    label: const Text('All'),
                    selected: _c.roleFilter == null,
                    onSelected: (_) => _c.setRoleFilter(null),
                  ),
                ),
                for (final r in GroupRole.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: Key('role_chip_${r.name}'),
                      label: Text(r.label),
                      selected: _c.roleFilter == r,
                      onSelected: (on) => _c.setRoleFilter(on ? r : null),
                    ),
                  ),
              ],
            ),
          ),
          if (_c.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _c.error!,
                key: const Key('members_error'),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _c.refresh,
              child: members.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            children: [
                              Icon(
                                _c.hasMemberFilter
                                    ? Icons.filter_alt_off_outlined
                                    : Icons.group_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _c.hasMemberFilter
                                    ? 'No members match'
                                    : 'No members',
                                key: Key(
                                  _c.hasMemberFilter
                                      ? 'members_no_match'
                                      : 'members_empty',
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_c.hasMemberFilter) ...[
                                const SizedBox(height: 12),
                                TextButton(
                                  key: const Key('members_clear_filters'),
                                  onPressed: () {
                                    _search.clear();
                                    _c.clearMemberFilters();
                                  },
                                  child: const Text('Clear filters'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: members.length,
                      itemBuilder: (_, i) => MemberTile(
                        member: members[i],
                        controller: _c,
                        onTap: () => MemberDetailSheet.show(
                          context,
                          member: members[i],
                          groupName: group.name,
                          isMe: members[i].userId == _c.currentUserId,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String title, String body, {Widget? action}) {
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  FilledButton(
                    onPressed: () => context.go('/groups'),
                    child: const Text('Back to Groups'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
