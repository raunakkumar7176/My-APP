import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/group.dart';
import '../../group/data/group_repository.dart';

/// Compact "My Groups" preview: first group the caller belongs to, or an
/// empty state pointing at Groups. Reuses [GroupRepository.myGroups] —
/// the same call the Groups list screen makes.
class GroupsPreviewCard extends StatefulWidget {
  const GroupsPreviewCard({super.key, this.repository});

  final GroupRepository? repository;

  @override
  State<GroupsPreviewCard> createState() => _GroupsPreviewCardState();
}

class _GroupsPreviewCardState extends State<GroupsPreviewCard> {
  late final GroupRepository _repo;
  bool _loading = true;
  String? _error;
  List<Group> _groups = const [];

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? const SupabaseGroupRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _repo.myGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your groups.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!, style: theme.textTheme.bodySmall)),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_groups.isEmpty) {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Icon(Icons.forum_outlined, color: theme.colorScheme.primary),
          ),
          title: const Text('Join a study group'),
          subtitle: const Text('Study with peers preparing for the same exam'),
          trailing: FilledButton(
            onPressed: () => context.push('/groups'),
            child: const Text('Explore'),
          ),
        ),
      );
    }

    final group = _groups.first;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          child: Icon(Icons.forum_outlined, color: theme.colorScheme.primary),
        ),
        title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}'
          '${_groups.length > 1 ? ' · ${_groups.length - 1} more group${_groups.length - 1 == 1 ? '' : 's'}' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/groups/${group.id}'),
      ),
    );
  }
}
