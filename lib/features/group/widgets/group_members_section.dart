import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../state/group_hub_controller.dart';
import 'member_tile.dart';

/// The Info screen's Members section: search over the full roster (already
/// loaded by the hub, up to the live 500-member cap) plus local "show more"
/// paging so a large group doesn't render every row at once.
class GroupMembersSection extends StatefulWidget {
  const GroupMembersSection({
    required this.controller,
    required this.onInvite,
    required this.onOpenRolePermissions,
    required this.onOpenRequests,
    super.key,
  });

  final GroupHubController controller;
  final VoidCallback onInvite;
  final VoidCallback onOpenRolePermissions;
  final VoidCallback onOpenRequests;

  @override
  State<GroupMembersSection> createState() => _GroupMembersSectionState();
}

class _GroupMembersSectionState extends State<GroupMembersSection> {
  static const _pageSize = 20;
  int _visibleCount = _pageSize;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    widget.controller.setMemberQuery(value);
    setState(() => _visibleCount = _pageSize);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.controller;
    final all = c.filteredMembers;
    final canManage = c.canManageMembers;
    final visible = all.take(_visibleCount).toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: AppRadius.xlBorder,
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // MemberTile's ListTile paints its background/ink on the nearest
      // Material ancestor — without this, Flutter asserts.
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Members (${c.members.length})',
                    key: const Key('hub_members_heading'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canManage)
                        IconButton(
                          key: const Key('group_info_open_requests'),
                          tooltip: 'Join requests & invitations',
                          icon: Badge.count(
                            count: c.pendingRequestCount,
                            isLabelVisible: c.pendingRequestCount > 0,
                            child: const Icon(
                              Icons.how_to_reg_outlined,
                              size: 20,
                            ),
                          ),
                          onPressed: widget.onOpenRequests,
                        ),
                      if (c.canManageRoles)
                        IconButton(
                          tooltip: 'Role permissions',
                          icon: const Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 20,
                          ),
                          onPressed: widget.onOpenRolePermissions,
                        ),
                      if (canManage)
                        TextButton.icon(
                          key: const Key('invite_member_action'),
                          onPressed: widget.onInvite,
                          icon: const Icon(Icons.person_add_alt, size: 16),
                          label: const Text('Invite'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('group_members_search_field'),
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search members…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.mdBorder,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    c.hasMemberFilter
                        ? 'No members match your search.'
                        : 'No members found.',
                    key: const Key('group_members_empty'),
                  ),
                )
              else ...[
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFF1F5F9),
                  ),
                  itemBuilder: (context, index) {
                    final m = visible[index];
                    return _FadeInListItem(
                      index: index,
                      child: MemberTile(
                        key: ValueKey('member_tile_${m.userId}'),
                        member: m,
                        controller: c,
                        onTap: () => MemberDetailSheet.show(
                          context,
                          member: m,
                          groupName: c.group?.name ?? '',
                          isMe: m.userId == c.currentUserId,
                        ),
                      ),
                    );
                  },
                ),
                if (visible.length < all.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(
                      child: TextButton(
                        key: const Key('group_members_load_more'),
                        onPressed: () =>
                            setState(() => _visibleCount += _pageSize),
                        child: Text(
                          'Show more (${all.length - visible.length})',
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A short, staggered fade + slide entrance for a list row (no new package).
class _FadeInListItem extends StatefulWidget {
  const _FadeInListItem({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_FadeInListItem> createState() => _FadeInListItemState();
}

class _FadeInListItemState extends State<_FadeInListItem> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.index * 35).clamp(0, 300);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
