import 'package:flutter/material.dart';

import '../../../core/models/group.dart';

/// Configuration step (R4 restart): identical to the legacy StepConfiguration
/// except that groups are injected by the creation controller instead of
/// being fetched inside the widget.
class ConfigurationStep extends StatefulWidget {
  const ConfigurationStep({
    required this.durationSec,
    required this.marksPerQuestion,
    required this.negativeMarks,
    required this.testMode,
    required this.groupId,
    required this.startsAt,
    required this.endsAt,
    required this.maxParticipants,
    required this.allowLateJoin,
    required this.accessCode,
    required this.joinCode,
    required this.onChanged,
    this.groups = const [],
    this.groupsLoading = false,
    super.key,
  });

  final int? durationSec;
  final double? marksPerQuestion;
  final double? negativeMarks;
  final String? testMode;
  final String? groupId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxParticipants;
  final bool allowLateJoin;
  final String? accessCode;
  final String? joinCode;
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Groups the user belongs to (loaded by the controller).
  final List<Group> groups;
  final bool groupsLoading;

  @override
  State<ConfigurationStep> createState() => _ConfigurationStepState();
}

class _ConfigurationStepState extends State<ConfigurationStep> {
  late final TextEditingController _durationController;
  late final TextEditingController _marksController;
  late final TextEditingController _negativeMarksController;
  late final TextEditingController _maxParticipantsController;
  late final TextEditingController _accessCodeController;
  late final TextEditingController _joinCodeController;
  late bool _allowLateJoin;
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: widget.durationSec != null
          ? (widget.durationSec! ~/ 60).toString()
          : '',
    );
    _marksController = TextEditingController(
      text: widget.marksPerQuestion?.toString() ?? '',
    );
    _negativeMarksController = TextEditingController(
      text: widget.negativeMarks?.toString() ?? '',
    );
    _maxParticipantsController = TextEditingController(
      text: widget.maxParticipants?.toString() ?? '',
    );
    _accessCodeController = TextEditingController(
      text: widget.accessCode ?? '',
    );
    _joinCodeController = TextEditingController(text: widget.joinCode ?? '');
    _allowLateJoin = widget.allowLateJoin;
    _startsAt = widget.startsAt;
    _endsAt = widget.endsAt;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _update();
      }
    });
  }

  @override
  void dispose() {
    _durationController.dispose();
    _marksController.dispose();
    _negativeMarksController.dispose();
    _maxParticipantsController.dispose();
    _accessCodeController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  void _update() {
    final isGroupMode = widget.testMode == 'group';
    widget.onChanged({
      'durationSec': _durationController.text.isNotEmpty
          ? int.tryParse(_durationController.text) != null
                ? int.parse(_durationController.text) * 60
                : null
          : null,
      'marksPerQuestion': double.tryParse(_marksController.text),
      'negativeMarks': double.tryParse(_negativeMarksController.text),
      'testMode': widget.testMode,
      'groupId': isGroupMode ? widget.groupId : null,
      'startsAt': _startsAt,
      'endsAt': _endsAt,
      'maxParticipants': int.tryParse(_maxParticipantsController.text),
      'allowLateJoin': _allowLateJoin,
      'accessCode': _accessCodeController.text.isNotEmpty
          ? _accessCodeController.text
          : null,
      'joinCode': _joinCodeController.text.isNotEmpty
          ? _joinCodeController.text
          : null,
    });
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startsAt ?? now)
          : (_endsAt ?? now.add(const Duration(hours: 1))),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        isStart
            ? (_startsAt ?? now)
            : (_endsAt ?? now.add(const Duration(hours: 1))),
      ),
    );
    if (time == null) return;

    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startsAt = dateTime;
      } else {
        _endsAt = dateTime;
      }
    });
    _update();
  }

  @override
  Widget build(BuildContext context) {
    final isGroupMode = widget.testMode == 'group';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Configuration',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure test settings, timing, and access.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _durationController,
            decoration: const InputDecoration(
              labelText: 'Duration (minutes)',
              hintText: 'e.g., 60',
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _marksController,
            decoration: const InputDecoration(
              labelText: 'Marks per Question',
              hintText: 'e.g., 4',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _negativeMarksController,
            decoration: const InputDecoration(
              labelText: 'Negative Marks',
              hintText: 'e.g., 1',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _update(),
          ),
          if (isGroupMode) ...[
            const SizedBox(height: 16),
            _buildGroupSelection(),
          ],
          const SizedBox(height: 24),
          Text(
            'Schedule',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildDateTimeRow(
            context,
            label: 'Start Time',
            dateTime: _startsAt,
            onPick: () => _pickDateTime(isStart: true),
            onClear: () {
              setState(() => _startsAt = null);
              _update();
            },
          ),
          const SizedBox(height: 8),
          _buildDateTimeRow(
            context,
            label: 'End Time',
            dateTime: _endsAt,
            onPick: () => _pickDateTime(isStart: false),
            onClear: () {
              setState(() => _endsAt = null);
              _update();
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Access Control',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _maxParticipantsController,
            decoration: const InputDecoration(
              labelText: 'Max Participants',
              hintText: 'Leave empty for unlimited',
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _accessCodeController,
            decoration: const InputDecoration(
              labelText: 'Access Code',
              hintText: 'Optional access code',
            ),
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _joinCodeController,
            decoration: const InputDecoration(
              labelText: 'Join Code',
              hintText: 'Optional join code',
            ),
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Allow Late Join'),
            value: _allowLateJoin,
            onChanged: (value) {
              setState(() => _allowLateJoin = value);
              _update();
            },
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelection() {
    final hasGroup = widget.groupId != null && widget.groupId!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group Selection',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (widget.groupsLoading && !hasGroup)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (widget.groups.isEmpty && !hasGroup)
              Text(
                'No groups found. Create or join a group first.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
              )
            else if (widget.groups.isEmpty && hasGroup) ...[
              Row(
                children: [
                  const Icon(Icons.group, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Group: ${widget.groupId}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onChanged({
                        'groupId': null,
                        'testMode': widget.testMode,
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue:
                    hasGroup && widget.groups.any((g) => g.id == widget.groupId)
                    ? widget.groupId
                    : null,
                decoration: const InputDecoration(labelText: 'Select Group'),
                items: widget.groups.map((group) {
                  return DropdownMenuItem(
                    value: group.id,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  widget.onChanged({
                    'groupId': value,
                    'testMode': widget.testMode,
                  });
                },
              ),
              if (hasGroup) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.group, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selected: ${widget.groups.firstWhere((g) => g.id == widget.groupId).name}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        widget.onChanged({
                          'groupId': null,
                          'testMode': widget.testMode,
                        });
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeRow(
    BuildContext context, {
    required String label,
    required DateTime? dateTime,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(
              dateTime != null
                  ? '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}'
                  : label,
            ),
          ),
        ),
        if (dateTime != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: onClear,
            tooltip: 'Clear',
          ),
        ],
      ],
    );
  }
}
