import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/group.dart';
import '../../core/models/test.dart';
import '../group/data/group_repository.dart';
import '../test/data/test_repository.dart';
import '../test/domain/test_lifecycle.dart';

/// Leaderboard entry point. Leaderboards are per group-test and
/// server-ranked (`rpc_get_leaderboard`, via [GroupLeaderboardScreen]) —
/// this screen only lets the user pick which group and which of that
/// group's completed tests to view; it never computes or shows a ranking
/// itself.
class LeaderboardHubScreen extends StatefulWidget {
  const LeaderboardHubScreen({super.key, this.groupRepository, this.testRepository});

  final GroupRepository? groupRepository;
  final TestRepository? testRepository;

  @override
  State<LeaderboardHubScreen> createState() => _LeaderboardHubScreenState();
}

class _LeaderboardHubScreenState extends State<LeaderboardHubScreen> {
  late final GroupRepository _groups;
  late final TestRepository _tests;

  bool _loading = true;
  String? _error;
  List<Group> _myGroups = [];
  String? _selectedGroupId;
  List<Test> _groupTests = [];
  bool _loadingTests = false;
  String? _testsError;

  @override
  void initState() {
    super.initState();
    _groups = widget.groupRepository ?? const SupabaseGroupRepository();
    _tests = widget.testRepository ?? const SupabaseTestRepository();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _groups.myGroups();
      if (!mounted) return;
      setState(() {
        _myGroups = groups;
        _loading = false;
      });
      if (groups.length == 1) _selectGroup(groups.first.id);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load your groups. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _selectGroup(String groupId) async {
    setState(() {
      _selectedGroupId = groupId;
      _loadingTests = true;
      _testsError = null;
      _groupTests = [];
    });
    try {
      final all = await _tests.listByGroup(groupId);
      final now = DateTime.now();
      // Only tests that have actually run have a leaderboard worth showing.
      final finished = [
        for (final t in all)
          if (TestLifecycle.isTerminal(t.status) ||
              TestLifecycle.categorize(
                    status: t.status,
                    testMode: t.testMode,
                    startsAt: t.startsAt,
                    endsAt: t.endsAt,
                    isSoftDeleted: t.isSoftDeleted,
                    now: now,
                  ) ==
                  ListingCategory.previous)
            t,
      ];
      if (!mounted) return;
      setState(() {
        _groupTests = finished;
        _loadingTests = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _testsError = e.message;
        _loadingTests = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testsError = 'Failed to load this group\'s tests. Please try again.';
        _loadingTests = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadGroups, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_myGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.leaderboard_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              const Text('No leaderboards yet'),
              const SizedBox(height: 4),
              Text(
                'Join a group to see leaderboards for its tests.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.push('/groups'),
                child: const Text('Browse Groups'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Group', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedGroupId,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          hint: const Text('Select a group'),
          items: [
            for (final g in _myGroups) DropdownMenuItem(value: g.id, child: Text(g.name)),
          ],
          onChanged: (id) {
            if (id != null) _selectGroup(id);
          },
        ),
        const SizedBox(height: 20),
        if (_selectedGroupId != null) _buildTestsList(),
      ],
    );
  }

  Widget _buildTestsList() {
    if (_loadingTests) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_testsError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(_testsError!)),
              TextButton(
                onPressed: () => _selectGroup(_selectedGroupId!),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_groupTests.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No finished tests in this group yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final t in _groupTests)
          Card(
            key: ValueKey(t.id),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/groups/$_selectedGroupId/tests/${t.id}/results/leaderboard'),
            ),
          ),
      ],
    );
  }
}
