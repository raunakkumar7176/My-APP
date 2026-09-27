import 'package:flutter/material.dart';

import '../../../core/models/group.dart';
import '../domain/attempt_policy.dart';
import '../domain/creation_settings.dart';
import '../domain/test_kind.dart';
import 'section_card.dart';
import 'setting_tile.dart';
import 'test_formatters.dart';

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
    this.attemptSettings = AttemptSettings.defaults,
    this.kind = TestKind.self,
    this.lateJoin = LateJoinSettings.defaults,
    this.questionConfig = QuestionConfig.none,
    this.autoSubmit = AutoSubmitSettings.defaults,
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
  final AttemptSettings attemptSettings;
  final TestKind kind;
  final LateJoinSettings lateJoin;
  final QuestionConfig questionConfig;
  final AutoSubmitSettings autoSubmit;
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
  late AttemptSettings _attempts;
  late LateJoinSettings _lateJoin;
  late QuestionConfig _questionConfig;
  late AutoSubmitSettings _autoSubmit;
  DateTime? _startsAt;

  static const _minDurationMinutes = 10;
  static const _maxDurationMinutes = 180;

  /// Derived from start + duration; kept only for the calculated display.
  DateTime? get _calculatedEnd => ScheduleMath.endFor(
    startsAt: _startsAt,
    durationSec: int.tryParse(_durationController.text) == null
        ? null
        : int.parse(_durationController.text) * 60,
  );

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
    _attempts = widget.attemptSettings;
    _lateJoin = widget.lateJoin;
    _questionConfig = widget.questionConfig;
    _autoSubmit = widget.autoSubmit;
    _startsAt = widget.startsAt;

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
      'endsAt': _calculatedEnd,
      'maxParticipants': int.tryParse(_maxParticipantsController.text),
      'allowLateJoin': _lateJoin.enabled,
      'attemptSettings': _attempts,
      'lateJoin': _lateJoin,
      'questionConfig': _questionConfig,
      'autoSubmit': _autoSubmit,
      'accessCode': _accessCodeController.text.isNotEmpty
          ? _accessCodeController.text
          : null,
      'joinCode': _joinCodeController.text.isNotEmpty
          ? _joinCodeController.text
          : null,
    });
  }

  void _setDurationMinutes(int minutes) {
    setState(() {
      _durationController.text = minutes.toString();
    });
    _update();
  }

  void _applyMarkingPreset({required double correct, required double negative}) {
    setState(() {
      _marksController.text = correct % 1 == 0
          ? correct.toInt().toString()
          : correct.toString();
      _negativeMarksController.text = negative % 1 == 0
          ? negative.toInt().toString()
          : negative.toString();
    });
    _update();
  }

  /// Start time only (local picker → local DateTime; the repository writes
  /// UTC). The end is derived from the duration, so no end picker exists.
  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now),
    );
    if (time == null || !mounted) return;

    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
    _update();
  }

  @override
  Widget build(BuildContext context) {
    final isGroupMode = widget.testMode == 'group';
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Configuration',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure test settings, timing, and access.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // ── Timing Section ──
          SectionCard(
            title: 'Timing',
            children: [
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes)',
                  hintText: 'e.g., 60',
                  prefixIcon: Icon(Icons.timer_outlined, size: 20),
                  suffixText: 'minutes',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _update(),
              ),
              const SizedBox(height: 4),
              Slider(
                value: (int.tryParse(_durationController.text) ??
                        _minDurationMinutes)
                    .clamp(_minDurationMinutes, _maxDurationMinutes)
                    .toDouble(),
                min: _minDurationMinutes.toDouble(),
                max: _maxDurationMinutes.toDouble(),
                divisions: (_maxDurationMinutes - _minDurationMinutes) ~/ 5,
                label: '${_durationController.text} min',
                onChanged: (v) => _setDurationMinutes(v.round()),
              ),
              Text(
                '$_minDurationMinutes – $_maxDurationMinutes minutes '
                '(type a value above for anything shorter, e.g. Quick Drill)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.kind.isScheduled) ...[
                const SizedBox(height: 16),
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
                const SizedBox(height: 12),
                SettingTile(
                  icon: Icons.schedule_outlined,
                  title: 'Calculated End Time',
                  subtitle: _calculatedEnd == null
                      ? 'Set a start time and duration'
                      : TestFormatters.dateTime(_calculatedEnd),
                ),
              ],
              const SizedBox(height: 12),
              SettingTile(
                icon: Icons.timer_off_outlined,
                title: 'Auto-submit on Timer Expiry',
                subtitle: _autoSubmit.enabled
                    ? 'Submits automatically when time runs out'
                    : 'At 00:00 the student is prompted to submit manually '
                        'instead of being auto-submitted',
                trailing: Switch(
                  value: _autoSubmit.enabled,
                  onChanged: (value) {
                    setState(
                      () => _autoSubmit = _autoSubmit.copyWith(enabled: value),
                    );
                    _update();
                  },
                ),
              ),
            ],
          ),

          // ── Marks Section ──
          SectionCard(
            title: 'Marks',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('UPSC Pattern (+2 / -0.66)'),
                    onPressed: () =>
                        _applyMarkingPreset(correct: 2, negative: 0.66),
                  ),
                  ActionChip(
                    label: const Text('SSC Pattern (+2 / -0.5)'),
                    onPressed: () =>
                        _applyMarkingPreset(correct: 2, negative: 0.5),
                  ),
                  ActionChip(
                    label: const Text('Standard (+1 / 0)'),
                    onPressed: () =>
                        _applyMarkingPreset(correct: 1, negative: 0),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _marksController,
                      decoration: const InputDecoration(
                        labelText: 'Correct Answer',
                        hintText: 'e.g., 4',
                        prefixIcon: Icon(Icons.add_circle_outline, size: 20),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _update(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _negativeMarksController,
                      decoration: const InputDecoration(
                        labelText: 'Negative Marks',
                        hintText: 'e.g., 1',
                        prefixIcon: Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _update(),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Question Configuration Section ──
          SectionCard(
            title: 'Question Configuration',
            subtitle:
                'MCQ only in V1 (4 options each). Set a total and difficulty '
                'distribution; the Review step checks questions against this target.',
            children: [
              _QuestionConfigFields(
                value: _questionConfig,
                maxTotal: widget.kind.maxQuestionTarget,
                onChanged: (v) {
                  setState(() => _questionConfig = v);
                  _update();
                },
              ),
            ],
          ),

          // ── Group Selection (Group Test only) ──
          if (isGroupMode) ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _buildGroupSelection(),
            ),
          ],

          // ── Late Joining (Scheduled kinds) ──
          if (widget.kind.supportsLateJoin) ...[
            SectionCard(
              title: 'Late Joining',
              subtitle: 'Allow new participants after the test starts',
              children: [
                SettingTile(
                  icon: Icons.timer_outlined,
                  title: 'Allow Late Joining',
                  trailing: Switch(
                    value: _lateJoin.enabled,
                    onChanged: (value) {
                      setState(
                        () => _lateJoin = _lateJoin.copyWith(enabled: value),
                      );
                      _update();
                    },
                  ),
                ),
                if (_lateJoin.enabled) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: const Key('late_join_minutes'),
                    initialValue: LateJoinSettings.allowedMinutes
                            .contains(_lateJoin.minutes)
                        ? _lateJoin.minutes
                        : LateJoinSettings.defaultMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Late Join Window (minutes after start)',
                    ),
                    items: [
                      for (final m in LateJoinSettings.allowedMinutes)
                        DropdownMenuItem(value: m, child: Text('$m minutes')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(
                        () => _lateJoin = _lateJoin.copyWith(minutes: v),
                      );
                      _update();
                    },
                  ),
                ],
              ],
            ),
          ],

          // ── Participants (Scheduled kinds) ──
          if (widget.kind.supportsMaxParticipants) ...[
            SectionCard(
              title: 'Participants',
              children: [
                TextFormField(
                  controller: _maxParticipantsController,
                  decoration: const InputDecoration(
                    labelText: 'Max Participants',
                    hintText: 'Leave empty for unlimited',
                    prefixIcon: Icon(Icons.people_outline, size: 20),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _update(),
                ),
              ],
            ),
          ],

          // ── Access Codes (Challenge with Friends) ──
          if (widget.kind.requiresJoinCode) ...[
            SectionCard(
              title: 'Access Codes',
              children: [
                TextFormField(
                  controller: _joinCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Join Code *',
                    hintText: 'Friends enter this code to join',
                    prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                  ),
                  onChanged: (_) => _update(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accessCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Access Code',
                    hintText: 'Optional extra access code',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                  onChanged: (_) => _update(),
                ),
              ],
            ),
          ],

          // ── Attempt Settings (every kind) ──
          SectionCard(
            title: 'Attempt Settings',
            subtitle:
                'Students can take this test once unless re-attempts are allowed. '
                'The limit is enforced by the server.',
            children: [
              SettingTile(
                icon: Icons.replay_outlined,
                title: 'Allow Re-attempt',
                trailing: Switch(
                  value: _attempts.allowReattempt,
                  onChanged: (value) {
                    setState(
                      () =>
                          _attempts = _attempts.copyWith(allowReattempt: value),
                    );
                    _update();
                  },
                ),
              ),
              if (_attempts.allowReattempt) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: const Key('max_attempts'),
                  initialValue: AttemptSettings.allowedMaxValues
                          .contains(_attempts.maxAttempts)
                      ? _attempts.maxAttempts
                      : 1,
                  decoration: const InputDecoration(
                    labelText: 'Maximum Attempts',
                  ),
                  items: [
                    for (final n in AttemptSettings.allowedMaxValues)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(
                      () => _attempts = _attempts.copyWith(maxAttempts: v),
                    );
                    _update();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelection() {
    final theme = Theme.of(context);
    final hasGroup = widget.groupId != null && widget.groupId!.isNotEmpty;

    return SectionCard(
      title: 'Group Selection',
      children: [
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
                  style: theme.textTheme.bodyMedium,
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
            decoration: const InputDecoration(
              labelText: 'Select Group',
              prefixIcon: Icon(Icons.groups_outlined, size: 20),
            ),
            items: widget.groups.map((group) {
              return DropdownMenuItem(
                value: group.id,
                // DropdownButton lays every item out twice: once in the
                // closed button (bounded width) and once inside an internal
                // IndexedStack it uses to measure all items uniformly —
                // that second pass hands each item's child UNBOUNDED width.
                // A bare Expanded/Flexible there throws "RenderFlex
                // children have non-zero flex but incoming width
                // constraints are unbounded" (a well-documented
                // DropdownMenuItem pitfall), and the resulting mid-layout
                // exception is exactly what produces "Cannot hit test a
                // render box with no size" (the RenderFlex left behind has
                // size: MISSING). Fix: give the Row a fixed, finite width
                // via SizedBox before the Expanded — it imposes a tight
                // width on its child regardless of its own incoming
                // constraints, so ellipsis truncation still works in both
                // the offstage sizing pass and the real menu.
                child: SizedBox(
                  width: 260,
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
                    style: theme.textTheme.bodyMedium,
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

/// Total + Easy/Medium/Hard target; validates E+M+H = Total inline.
class _QuestionConfigFields extends StatefulWidget {
  const _QuestionConfigFields({
    required this.value,
    required this.onChanged,
    this.maxTotal,
  });

  final QuestionConfig value;
  final int? maxTotal;
  final ValueChanged<QuestionConfig> onChanged;

  @override
  State<_QuestionConfigFields> createState() => _QuestionConfigFieldsState();
}

class _QuestionConfigFieldsState extends State<_QuestionConfigFields> {
  late final TextEditingController _total;
  late final TextEditingController _easy;
  late final TextEditingController _medium;
  late final TextEditingController _hard;

  @override
  void initState() {
    super.initState();
    String s(int v) => v == 0 ? '' : '$v';
    _total = TextEditingController(text: s(widget.value.total));
    _easy = TextEditingController(text: s(widget.value.easy));
    _medium = TextEditingController(text: s(widget.value.medium));
    _hard = TextEditingController(text: s(widget.value.hard));
  }

  @override
  void dispose() {
    _total.dispose();
    _easy.dispose();
    _medium.dispose();
    _hard.dispose();
    super.dispose();
  }

  QuestionConfig get _current => QuestionConfig(
    total: int.tryParse(_total.text) ?? 0,
    easy: int.tryParse(_easy.text) ?? 0,
    medium: int.tryParse(_medium.text) ?? 0,
    hard: int.tryParse(_hard.text) ?? 0,
  );

  void _emit() => widget.onChanged(_current);

  Widget _field(String label, TextEditingController c, {Key? key}) => Expanded(
    child: TextFormField(
      key: key,
      controller: c,
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      onChanged: (_) {
        setState(() {});
        _emit();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final v = _current;
    final overMax = widget.maxTotal != null && v.total > widget.maxTotal!;
    final status = !v.isSet
        ? 'No target set (optional)'
        : overMax
            ? 'Total cannot exceed ${widget.maxTotal} for this test type'
            : v.isValid
                ? 'Total ${v.sum} / ${v.total}'
                : 'Total ${v.sum} / ${v.total} — Easy + Medium + Hard must equal Total';
    final ok = !v.isSet || (v.isValid && !overMax);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _field('Total Questions', _total, key: const Key('qc_total')),
            const SizedBox(width: 12),
            const Expanded(child: Text('Question Type: MCQ')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _field('Easy', _easy, key: const Key('qc_easy')),
            const SizedBox(width: 8),
            _field('Medium', _medium, key: const Key('qc_medium')),
            const SizedBox(width: 8),
            _field('Hard', _hard, key: const Key('qc_hard')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ok
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            status,
            key: const Key('qc_status'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ok ? null : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
