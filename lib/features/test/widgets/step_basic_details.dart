import 'package:flutter/material.dart';

import '../../../core/models/test_kind.dart';

/// One entry of the "Test Type" picker: the DB `test_mode` it maps to plus,
/// for the Self family, the `settings.test_kind`.
class TestTypeOption {
  const TestTypeOption({required this.mode, required this.kind});

  final String mode;
  final TestKind kind;

  String get label => testTypeLabel(testMode: mode, kind: kind);

  /// Stable value for the dropdown.
  String get value => '$mode:${kind.dbValue}';

  static const all = [
    TestTypeOption(mode: 'self', kind: TestKind.self),
    TestTypeOption(mode: 'self', kind: TestKind.practice),
    TestTypeOption(mode: 'self', kind: TestKind.quick),
    TestTypeOption(mode: 'self', kind: TestKind.sectional),
    TestTypeOption(mode: 'live', kind: TestKind.self),
    TestTypeOption(mode: 'group', kind: TestKind.self),
  ];

  /// Resolves the option for a stored (mode, kind); unknown modes and any
  /// non-self mode ignore the kind.
  static TestTypeOption? resolve(String? mode, TestKind kind) {
    if (mode == null) return null;
    final effectiveKind = mode == 'self' ? kind : TestKind.self;
    for (final o in all) {
      if (o.mode == mode && o.kind == effectiveKind) return o;
    }
    return null;
  }
}

class StepBasicDetails extends StatelessWidget {
  const StepBasicDetails({
    required this.title,
    required this.description,
    required this.testMode,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onTestModeChanged,
    required this.titleError,
    this.testKind = TestKind.self,
    this.onTestKindChanged,
    super.key,
  });

  final String title;
  final String description;
  final String? testMode;
  final TestKind testKind;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final ValueChanged<String?> onTestModeChanged;

  /// Called with the Self-family kind whenever the type changes (always
  /// [TestKind.self] for Challenge with Friends / Group Test).
  final ValueChanged<TestKind>? onTestKindChanged;
  final String? titleError;

  String? get _kindHint {
    if (testMode != 'self') return null;
    switch (testKind) {
      case TestKind.practice:
        return 'Practice: no schedule, repeat as often as you like. '
            'A time limit is still applied by the server for now.';
      case TestKind.quick:
        return 'Quick: a short test — aim for 5–10 questions, about 10 minutes.';
      case TestKind.sectional:
        return 'Sectional: cover several subjects/topics via the Syllabus step.';
      case TestKind.self:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = TestTypeOption.resolve(testMode, testKind);
    final hint = _kindHint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Basic Details',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the basic information for your test.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            initialValue: title,
            decoration: InputDecoration(
              labelText: 'Test Title *',
              hintText: 'Enter a descriptive title',
              errorText: titleError,
            ),
            onChanged: onTitleChanged,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: description,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Optional description for the test',
            ),
            onChanged: onDescriptionChanged,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selected?.value,
            decoration: InputDecoration(
              labelText: 'Test Type',
              helperText: hint,
              helperMaxLines: 3,
            ),
            items: [
              for (final o in TestTypeOption.all)
                DropdownMenuItem(value: o.value, child: Text(o.label)),
            ],
            onChanged: (value) {
              final option = TestTypeOption.all
                  .cast<TestTypeOption?>()
                  .firstWhere((o) => o!.value == value, orElse: () => null);
              if (option == null) return;
              onTestModeChanged(option.mode);
              onTestKindChanged?.call(option.kind);
            },
          ),
        ],
      ),
    );
  }
}
