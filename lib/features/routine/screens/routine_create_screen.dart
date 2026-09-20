import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/subject.dart';
import '../../../core/models/syllabus_node.dart';
import '../../../core/services/subject_service.dart';
import '../../../core/services/syllabus_service.dart';
import '../domain/routine_schedule.dart';
import '../state/routine_controller.dart';

typedef SubjectLoader = Future<List<Subject>> Function();
typedef TopicLoader = Future<List<SyllabusNode>> Function(String subjectId);

/// Create / edit one routine task: Subject → Chapter/Topic → Activity, a
/// wall-clock slot, optional target duration and the weekly repeat.
///
/// Persisted as one `routines` row: `subject_id` + a structured title
/// (`RoutineSchedule.composeTitle`) + `start_time`/`end_time`/`weekdays`/
/// `target_duration_minutes`/`reminder_enabled`. Saving is refused on
/// invalid times or an overlapping active routine — never silently.
class RoutineCreateScreen extends StatefulWidget {
  const RoutineCreateScreen({
    super.key,
    this.routineId,
    this.controller,
    this.subjectLoader,
    this.topicLoader,
  });

  /// If provided, the screen operates in edit mode.
  final String? routineId;

  /// Injection points for tests; production uses the live services.
  final RoutineController? controller;
  final SubjectLoader? subjectLoader;
  final TopicLoader? topicLoader;

  @override
  State<RoutineCreateScreen> createState() => _RoutineCreateScreenState();
}

class _RoutineCreateScreenState extends State<RoutineCreateScreen> {
  late final RoutineController _controller;
  late final bool _ownsController;
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _durationController = TextEditingController();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  final Set<int> _selectedWeekdays = {0, 1, 2, 3, 4, 5, 6};
  String? _selectedSubjectId;
  String? _selectedTopic; // syllabus node name (what the title stores)
  String? _selectedActivity;
  bool _reminderEnabled = true;

  List<Subject> _subjects = [];
  List<SyllabusNode> _topics = [];
  bool _isLoadingSubjects = true;
  bool _isLoadingTopics = false;
  bool _isLoadingRoutine = false;
  bool _isSaving = false;
  String? _error;
  String? _loadError;
  String? _pendingTitle; // raw title awaiting topic names in edit mode

  bool get _isEditMode => widget.routineId != null;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? RoutineController();
    _loadSubjects();
    if (_isEditMode) _loadRoutine();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _titleController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await (widget.subjectLoader ?? SubjectService.loadSubjects)();
      if (mounted) setState(() => _subjects = subjects);
    } catch (_) {
      // Subject is optional; the form still works without the list.
    } finally {
      if (mounted) setState(() => _isLoadingSubjects = false);
    }
  }

  Future<void> _loadTopics(String? subjectId) async {
    if (subjectId == null) {
      setState(() {
        _topics = [];
        _selectedTopic = null;
      });
      return;
    }
    setState(() => _isLoadingTopics = true);
    try {
      final nodes = await (widget.topicLoader ?? SyllabusService.loadNodesForSubject)(subjectId);
      if (!mounted) return;
      setState(() {
        _topics = nodes;
        if (_selectedTopic != null && !nodes.any((n) => n.name == _selectedTopic)) {
          _selectedTopic = null;
        }
      });
      _applyPendingTitle();
    } catch (_) {
      if (mounted) setState(() => _topics = []);
    } finally {
      if (mounted) setState(() => _isLoadingTopics = false);
    }
  }

  Future<void> _loadRoutine() async {
    setState(() {
      _isLoadingRoutine = true;
      _loadError = null;
    });
    try {
      final routine = await _controller.getById(widget.routineId!);
      if (!mounted) return;
      if (routine == null) {
        setState(() {
          _loadError = 'Routine not found';
          _isLoadingRoutine = false;
        });
        return;
      }
      final s = RoutineSchedule.toMinutes(routine.startTime) ?? 9 * 60;
      final e = RoutineSchedule.toMinutes(routine.endTime) ?? 10 * 60;
      setState(() {
        _startTime = TimeOfDay(hour: s ~/ 60, minute: s % 60);
        _endTime = TimeOfDay(hour: e ~/ 60, minute: e % 60);
        _selectedWeekdays
          ..clear()
          ..addAll(routine.weekdays);
        _selectedSubjectId = routine.subjectId;
        _reminderEnabled = routine.reminderEnabled;
        _durationController.text = routine.targetDurationMinutes?.toString() ?? '';
        _pendingTitle = routine.title;
        _isLoadingRoutine = false;
      });
      _applyPendingTitle();
      if (routine.subjectId != null) await _loadTopics(routine.subjectId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e is AppError ? e.message : 'Failed to load routine';
          _isLoadingRoutine = false;
        });
      }
    }
  }

  /// Splits the stored title into base / topic / activity. Runs once the
  /// subject's topic names are known so a topic segment is recognised.
  void _applyPendingTitle() {
    final raw = _pendingTitle;
    if (raw == null) return;
    final parsed = RoutineSchedule.parseTitle(
      raw,
      knownTopics: _topics.map((n) => n.name),
    );
    setState(() {
      _titleController.text = parsed.base;
      _selectedActivity = parsed.activity;
      if (parsed.topic != null) _selectedTopic = parsed.topic;
    });
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;

    final durationText = _durationController.text.trim();
    int? targetDuration;
    if (durationText.isNotEmpty) {
      targetDuration = int.tryParse(durationText);
      if (targetDuration == null) {
        setState(() => _error = 'Duration must be a whole number of minutes');
        return;
      }
    }
    final weekdays = _selectedWeekdays.toList()..sort();
    final start = _hhmm(_startTime);
    final end = _hhmm(_endTime);

    final problem = RoutineSchedule.validate(
      startTime: start,
      endTime: end,
      weekdays: weekdays,
      targetDurationMinutes: targetDuration,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final conflict = await _controller.hasConflict(
        startTime: start,
        endTime: end,
        weekdays: weekdays,
        excludeId: widget.routineId,
      );
      if (conflict) {
        if (mounted) {
          setState(() {
            _error = 'This time overlaps another active routine on the same day. '
                'Change the time or days.';
            _isSaving = false;
          });
        }
        return;
      }

      final title = RoutineSchedule.composeTitle(
        base: _titleController.text,
        topic: _selectedTopic,
        activity: _selectedActivity,
      );

      if (_isEditMode) {
        await _controller.updateRoutine(
          id: widget.routineId!,
          title: title,
          startTime: start,
          endTime: end,
          weekdays: weekdays,
          subjectId: _selectedSubjectId,
          clearSubject: _selectedSubjectId == null,
          reminderEnabled: _reminderEnabled,
          targetDurationMinutes: targetDuration,
          clearTargetDuration: targetDuration == null,
        );
      } else {
        await _controller.createRoutine(
          title: title,
          startTime: start,
          endTime: end,
          weekdays: weekdays,
          subjectId: _selectedSubjectId,
          reminderEnabled: _reminderEnabled,
          targetDurationMinutes: targetDuration,
        );
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is AppError
              ? e.message
              : 'Could not check for conflicts. Please try again.';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRoutine) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Routine')),
        body: const Center(
          child: CircularProgressIndicator(key: Key('routine_form_loading')),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Routine')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_loadError!, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('routine_form_retry'),
                onPressed: _loadRoutine,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Routine' : 'Create Routine'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) _buildErrorBanner(),
            _buildSubjectDropdown(),
            const SizedBox(height: 16),
            if (_selectedSubjectId != null) ...[
              _buildTopicDropdown(),
              const SizedBox(height: 16),
            ],
            _buildActivityDropdown(),
            const SizedBox(height: 16),
            _buildTitleField(),
            const SizedBox(height: 16),
            _buildTimeRow(),
            const SizedBox(height: 16),
            _buildDurationField(),
            const SizedBox(height: 16),
            _buildWeekdayPicker(),
            const SizedBox(height: 16),
            _buildReminderSwitch(),
            const SizedBox(height: 24),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      key: const Key('routine_form_error'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleField() {
    final preview = RoutineSchedule.composeTitle(
      base: _titleController.text,
      topic: _selectedTopic,
      activity: _selectedActivity,
    );
    return TextFormField(
      key: const Key('routine_title'),
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Title (optional)',
        hintText: 'e.g. Morning study',
        helperText: 'Shown as: $preview',
        border: const OutlineInputBorder(),
      ),
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildTimeRow() {
    return Row(
      children: [
        Expanded(
          child: _buildTimeTile(
            key: const Key('routine_start_time'),
            label: 'Start Time',
            time: _startTime,
            onTap: () => _pickTime(isStart: true),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildTimeTile(
            key: const Key('routine_end_time'),
            label: 'End Time',
            time: _endTime,
            onTap: () => _pickTime(isStart: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeTile({
    required Key key,
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          RoutineSchedule.format12h(_hhmm(time)),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildWeekdayPicker() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repeat on',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final isSelected = _selectedWeekdays.contains(i);
            return GestureDetector(
              key: Key('routine_weekday_$i'),
              onTap: () => setState(() {
                if (isSelected) {
                  _selectedWeekdays.remove(i);
                } else {
                  _selectedWeekdays.add(i);
                }
              }),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryLight
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  RoutineSchedule.weekdayShort[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSubjectDropdown() {
    if (_isLoadingSubjects) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Subject (optional)',
          border: OutlineInputBorder(),
        ),
        child: Text('Loading subjects...'),
      );
    }
    return DropdownButtonFormField<String?>(
      key: const Key('routine_subject'),
      initialValue: _selectedSubjectId,
      decoration: const InputDecoration(
        labelText: 'Subject (optional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No subject')),
        ..._subjects.map(
          (s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
        ),
      ],
      onChanged: (value) {
        setState(() => _selectedSubjectId = value);
        _loadTopics(value);
      },
    );
  }

  Widget _buildTopicDropdown() {
    if (_isLoadingTopics) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Chapter / Topic (optional)',
          border: OutlineInputBorder(),
        ),
        child: Text('Loading syllabus...'),
      );
    }
    final byId = {for (final n in _topics) n.id: n};
    String label(SyllabusNode n) {
      final parent = n.parentId != null ? byId[n.parentId] : null;
      return parent == null ? n.name : '${parent.name} › ${n.name}';
    }
    final sorted = [..._topics]..sort((a, b) => label(a).compareTo(label(b)));
    return DropdownButtonFormField<String?>(
      // Re-keyed per subject so the form field never shows a stale topic.
      key: Key('routine_topic_$_selectedSubjectId'),
      initialValue: _selectedTopic,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Chapter / Topic (optional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No topic')),
        ...sorted.map(
          (n) => DropdownMenuItem<String?>(
            value: n.name,
            child: Text(label(n), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _selectedTopic = value),
    );
  }

  Widget _buildActivityDropdown() {
    return DropdownButtonFormField<String?>(
      key: const Key('routine_activity'),
      initialValue: _selectedActivity,
      decoration: const InputDecoration(
        labelText: 'Study Activity (optional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No activity')),
        ...RoutineSchedule.activities.map(
          (a) => DropdownMenuItem<String?>(value: a, child: Text(a)),
        ),
      ],
      onChanged: (value) => setState(() => _selectedActivity = value),
    );
  }

  Widget _buildDurationField() {
    return TextFormField(
      key: const Key('routine_duration'),
      controller: _durationController,
      decoration: const InputDecoration(
        labelText: 'Target duration in minutes (optional)',
        hintText: 'e.g. 45',
        border: OutlineInputBorder(),
        suffixText: 'min',
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildReminderSwitch() {
    return SwitchListTile(
      key: const Key('routine_reminder'),
      title: const Text('Daily Reminder'),
      subtitle: const Text("Get notified when it's time to study"),
      value: _reminderEnabled,
      onChanged: (value) => setState(() => _reminderEnabled = value),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        key: const Key('routine_save'),
        onPressed: _isSaving ? null : _save,
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_isEditMode ? 'Save Changes' : 'Create Routine'),
      ),
    );
  }
}
