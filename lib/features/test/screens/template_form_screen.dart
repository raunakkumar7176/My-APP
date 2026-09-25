import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../domain/test_kind.dart';
import '../state/template_form_controller.dart';

/// G19 — Create/edit screen for test templates.
/// Reuses the same configuration fields as the Test Creation wizard's
/// Basic Details + Configuration steps, but saves as a template instead.
class TemplateFormScreen extends StatefulWidget {
  const TemplateFormScreen({this.templateId, this.initialConfig, super.key});

  final String? templateId;

  /// When provided (from "Save as Template" in test creation), the form
  /// is pre-populated with these values.
  final Map<String, dynamic>? initialConfig;

  @override
  State<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends State<TemplateFormScreen> {
  late final TemplateFormController _c;
  late final bool _owns;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  TestKind _kind = TestKind.self;
  int? _durationSec;
  double? _marksPerQuestion;
  double? _negativeMarks;

  @override
  void initState() {
    super.initState();
    _owns = widget.templateId == null;
    _c = TemplateFormController(editingTemplateId: widget.templateId);
    _c.addListener(_onChanged);

    if (widget.initialConfig != null) {
      _applyConfig(widget.initialConfig!);
      _c.presetFromConfiguration(
        templateTitle: widget.initialConfig!['title'] as String? ?? '',
        templateDescription:
            widget.initialConfig!['description'] as String? ?? '',
        templateGroupId: widget.initialConfig!['group_id'] as String?,
        templateConfiguration:
            widget.initialConfig!['configuration'] as Map<String, dynamic>? ??
            {},
      );
      _titleCtrl.text = _c.title;
      _descCtrl.text = _c.description;
    } else if (widget.templateId != null) {
      _c.loadForEdit().then((_) {
        if (mounted) {
          _titleCtrl.text = _c.title;
          _descCtrl.text = _c.description;
          _applyConfig(_c.configuration);
          setState(() {});
        }
      });
    }
  }

  void _applyConfig(Map<String, dynamic> config) {
    final kindName = config['kind'] as String?;
    if (kindName != null) {
      _kind = TestKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => TestKind.self,
      );
    }
    _durationSec = (config['duration_sec'] as num?)?.toInt();
    _marksPerQuestion = (config['marks_per_question'] as num?)?.toDouble();
    _negativeMarks = (config['negative_marks'] as num?)?.toDouble();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    if (_owns) _c.dispose();
    super.dispose();
  }

  void _snack(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _save() async {
    try {
      _c.setTitle(_titleCtrl.text);
      _c.setDescription(_descCtrl.text);
      _c.setConfiguration({
        'kind': _kind.name,
        'test_mode': _kind == TestKind.group ? 'group' : 'self',
        if (_durationSec != null) 'duration_sec': _durationSec,
        if (_marksPerQuestion != null) 'marks_per_question': _marksPerQuestion,
        if (_negativeMarks != null) 'negative_marks': _negativeMarks,
      });
      await _c.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _c.isPersisted ? 'Template updated' : 'Template created',
          ),
        ),
      );
      context.pop();
    } on ValidationError catch (e) {
      if (mounted) _snack(e.message, error: true);
    } on AppError catch (e) {
      if (mounted) _snack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_c.loadError!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final busy = _c.isBusy;
    return Scaffold(
      appBar: AppBar(
        title: Text(_c.isPersisted ? 'Edit Template' : 'Create Template'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: busy ? null : () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('template_title'),
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Template Name',
                hintText: 'e.g. Weekly Physics Quiz',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('template_description'),
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Brief description of this template',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            Text(
              'Test Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TestKind>(
              key: const Key('template_kind'),
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Test Kind',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final k in TestKind.creatable)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? TestKind.self),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('template_duration'),
              decoration: InputDecoration(
                labelText: 'Duration (minutes)',
                hintText: 'e.g. 60',
                border: const OutlineInputBorder(),
                suffixText: _durationSec != null
                    ? '${(_durationSec! / 60).round()} min'
                    : '',
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final m = int.tryParse(v);
                setState(() => _durationSec = m != null ? m * 60 : null);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('template_marks'),
              decoration: const InputDecoration(
                labelText: 'Marks per Question',
                hintText: 'e.g. 1',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final m = double.tryParse(v);
                setState(() => _marksPerQuestion = m);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('template_negative'),
              decoration: const InputDecoration(
                labelText: 'Negative Marks',
                hintText: 'e.g. 0.25',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final m = double.tryParse(v);
                setState(() => _negativeMarks = m);
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('template_save'),
                onPressed: busy || !_c.canSave ? null : _save,
                child: Text(
                  busy
                      ? 'Saving…'
                      : (_c.isPersisted
                            ? 'Update Template'
                            : 'Create Template'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
