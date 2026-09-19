import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/test.dart';
import '../../test/domain/backend_mapping.dart';
import '../../test/domain/test_lifecycle.dart';
import '../../test/widgets/test_formatters.dart';
import '../domain/group_test_management.dart';
import '../state/group_tests_controller.dart';

/// Group test management (G10): the group's tests in management sections
/// plus the lifecycle actions the live backend supports. Creation, question
/// editing and the participant flows stay in the R4 screens (`/tests/...`);
/// this screen opens them pre-scoped to the group. Every action is
/// re-checked by the server; the gates here are UX.
class GroupTestsScreen extends StatefulWidget {
  const GroupTestsScreen({required this.groupId, this.controller, super.key});

  final String groupId;
  final GroupTestsController? controller;

  @override
  State<GroupTestsScreen> createState() => _GroupTestsScreenState();
}

class _GroupTestsScreenState extends State<GroupTestsScreen> {
  late final GroupTestsController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupTestsController(groupId: widget.groupId);
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

  Future<void> _create() async {
    // R4 wizard, pre-scoped: kind = Group Test, group fixed to this one.
    await context.push('/tests/create?group=${widget.groupId}');
    if (mounted) await _c.refresh();
  }

  Future<void> _open(Test t) async {
    await context.push('/tests/${t.id}');
    if (mounted) await _c.refresh();
  }

  Future<void> _edit(Test t) async {
    await context.push('/tests/${t.id}/edit');
    if (mounted) await _c.refresh();
  }

  Future<void> _viewResults(Test t) async {
    await context.push('/groups/${widget.groupId}/tests/${t.id}/results');
    if (mounted) await _c.refresh();
  }

  bool _hasResults(Test t) =>
      t.status == TestStatus.completed ||
      t.status == TestStatus.ended ||
      t.status == TestStatus.evaluated;

  Future<void> _manage(Test t) async {
    await GroupTestManageSheet.show(
      context,
      controller: _c,
      test: t,
      onOpen: () => _open(t),
      onEdit: () => _edit(t),
      onViewResults: _hasResults(t) ? () => _viewResults(t) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group tests')),
        body: const Center(
          child: CircularProgressIndicator(key: Key('group_tests_loading')),
        ),
      );
    }
    if (_c.accessDenied) {
      return _message(
        key: const Key('group_tests_denied'),
        icon: Icons.lock_outline,
        title: 'Group not available',
        body: 'This group does not exist, or you are not a member of it.',
      );
    }
    if (_c.group == null) {
      return _message(
        key: const Key('group_tests_error'),
        icon: Icons.error_outline,
        title: 'Could not load group tests',
        body: _c.error ?? 'Please try again.',
        action: FilledButton(
          key: const Key('group_tests_retry'),
          onPressed: _c.load,
          child: const Text('Retry'),
        ),
      );
    }
    final sections = _c.sections;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_c.group!.name} · Tests'),
        actions: [
          if (_c.canCreateTest)
            IconButton(
              key: const Key('create_group_test'),
              tooltip: 'New group test',
              icon: const Icon(Icons.add),
              onPressed: _c.isBusy ? null : _create,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          key: const Key('group_tests_list'),
          padding: const EdgeInsets.all(16),
          children: [
            if (_c.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _c.error!,
                  key: const Key('group_tests_action_error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            if (!_c.canManage)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'You can view this group\'s tests. Managing them needs a '
                  'test permission from the group leaders.',
                  key: const Key('group_tests_readonly_note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_c.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No tests in this group yet.',
                  key: const Key('group_tests_empty'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final s in GroupTestSection.values)
                if (sections[s]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      '${s.label} · ${sections[s]!.length}',
                      key: Key('section_${s.name}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final t in sections[s]!) _tile(t),
                ],
          ],
        ),
      ),
    );
  }

  Widget _tile(Test t) {
    final acting = _c.actingTestId == t.id;
    return Card(
      key: Key('group_test_${t.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(t.title),
        subtitle: Text(
          '${TestLifecycle.statusLabel(t.status)} · '
          '${TestFormatters.duration(t.durationSec)}'
          '${t.startsAt != null ? ' · starts ${TestFormatters.dateTime(t.startsAt)}' : ''}',
          key: Key('group_test_meta_${t.id}'),
        ),
        trailing: acting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                key: Key('manage_${t.id}'),
                tooltip: 'Manage',
                icon: const Icon(Icons.more_vert),
                onPressed: _c.isBusy ? null : () => _manage(t),
              ),
        onTap: _c.isBusy ? null : () => _open(t),
      ),
    );
  }

  Widget _message({
    required Key key,
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group tests')),
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
                    onPressed: () => context.go('/groups/${widget.groupId}'),
                    child: const Text('Back to group'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Management view for one group test: safe fields (never the answer key)
/// and the lifecycle actions the caller may perform.
class GroupTestManageSheet extends StatefulWidget {
  const GroupTestManageSheet({
    required this.controller,
    required this.test,
    required this.onOpen,
    required this.onEdit,
    this.onViewResults,
    super.key,
  });

  final GroupTestsController controller;
  final Test test;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback? onViewResults;

  static Future<void> show(
    BuildContext context, {
    required GroupTestsController controller,
    required Test test,
    required VoidCallback onOpen,
    required VoidCallback onEdit,
    VoidCallback? onViewResults,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupTestManageSheet(
        controller: controller,
        test: test,
        onOpen: onOpen,
        onEdit: onEdit,
        onViewResults: onViewResults,
      ),
    );
  }

  @override
  State<GroupTestManageSheet> createState() => _GroupTestManageSheetState();
}

class _GroupTestManageSheetState extends State<GroupTestManageSheet> {
  GroupTestsController get c => widget.controller;

  /// Always the freshest server copy of this test (after a mutation the
  /// controller re-read the list).
  Test get t =>
      c.tests.where((x) => x.id == widget.test.id).firstOrNull ?? widget.test;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _publish() async {
    final ok = await c.publish(t);
    if (!mounted) return;
    _snack(ok ? 'Test published.' : (c.error ?? 'Could not publish.'), error: !ok);
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive test?'),
        content: const Text(
          'The test is hidden from members and marked archived. Existing '
          'attempts and results are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_archive_test'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await c.archive(t);
    if (!mounted) return;
    _snack(ok ? 'Test archived.' : (c.error ?? 'Could not archive.'), error: !ok);
  }

  Future<void> _deleteDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete draft?'),
        content: const Text('The draft is removed from the group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_draft'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await c.deleteDraft(t);
    if (!mounted) return;
    _snack(ok ? 'Draft deleted.' : (c.error ?? 'Could not delete.'), error: !ok);
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _schedule() async {
    DateTime? start = t.startsAt?.toLocal();
    DateTime? end = t.endsAt?.toLocal();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Schedule test'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('schedule_start'),
                title: const Text('Starts'),
                subtitle: Text(TestFormatters.dateTime(start)),
                onTap: () async {
                  final v = await _pick(start);
                  if (v != null) setLocal(() => start = v);
                },
              ),
              ListTile(
                key: const Key('schedule_end'),
                title: const Text('Ends'),
                subtitle: Text(TestFormatters.dateTime(end)),
                onTap: () async {
                  final v = await _pick(end ?? start);
                  if (v != null) setLocal(() => end = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_schedule'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await c.schedule(t, startsAt: start, endsAt: end);
    if (!mounted) return;
    _snack(ok ? 'Schedule saved.' : (c.error ?? 'Could not schedule.'), error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final test = t;
    final busy = c.isBusy;
    final kind = BackendMapping.fromBackend(test.testMode, test.settings);
    final creator = c.isCreator(test) ? 'You' : 'Another manager';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('group_test_manage_sheet'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(test.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${TestLifecycle.statusLabel(test.status)} · ${kind.label}',
                key: const Key('manage_status'),
              ),
              if ((test.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(test.description!.trim()),
              ],
              const SizedBox(height: 12),
              _row('Duration', TestFormatters.duration(test.durationSec)),
              _row('Marks per question', '${test.marksPerQuestion ?? '--'}'),
              _row('Negative marks', '${test.negativeMarks ?? '--'}'),
              _row('Starts', TestFormatters.dateTime(test.startsAt)),
              _row('Ends', TestFormatters.dateTime(test.endsAt)),
              _row('Group', c.group?.name ?? '--'),
              _row('Created by', creator),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('manage_open'),
                    onPressed: busy ? null : widget.onOpen,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open'),
                  ),
                  if (c.canEdit(test))
                    OutlinedButton.icon(
                      key: const Key('manage_edit'),
                      onPressed: busy ? null : widget.onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit draft'),
                    ),
                  if (c.canSchedule(test))
                    OutlinedButton.icon(
                      key: const Key('manage_schedule'),
                      onPressed: busy ? null : _schedule,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: const Text('Schedule'),
                    ),
                  if (c.canPublish(test))
                    FilledButton.icon(
                      key: const Key('manage_publish'),
                      onPressed: busy ? null : _publish,
                      icon: const Icon(Icons.publish, size: 18),
                      label: const Text('Publish'),
                    ),
                  if (c.canArchive(test))
                    OutlinedButton.icon(
                      key: const Key('manage_archive'),
                      onPressed: busy ? null : _archive,
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('Archive'),
                    ),
                  if (c.canDeleteDraft(test))
                    OutlinedButton.icon(
                      key: const Key('manage_delete_draft'),
                      onPressed: busy ? null : _deleteDraft,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete draft'),
                    ),
                  if (widget.onViewResults != null)
                    OutlinedButton.icon(
                      key: const Key('manage_view_results'),
                      onPressed: busy ? null : widget.onViewResults,
                      icon: const Icon(Icons.bar_chart, size: 18),
                      label: const Text('Results'),
                    ),
                ],
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(key: Key('manage_busy')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 150, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
