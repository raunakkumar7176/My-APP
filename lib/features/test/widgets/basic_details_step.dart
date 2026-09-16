import 'package:flutter/material.dart';

import '../domain/test_kind.dart';

/// Title, description and the product-level Test Type picker.
/// The picker works purely in [TestKind]; storage mapping happens in the
/// controller via BackendMapping.
class BasicDetailsStep extends StatelessWidget {
  const BasicDetailsStep({
    required this.title,
    required this.description,
    required this.kind,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onKindChanged,
    this.titleError,
    super.key,
  });

  final String title;
  final String description;
  final TestKind kind;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final ValueChanged<TestKind> onKindChanged;
  final String? titleError;

  static String? hintFor(TestKind kind) {
    switch (kind) {
      case TestKind.practice:
        return 'Practice: no schedule, repeat as often as you like. '
            'A time limit is still applied by the server for now.';
      case TestKind.quick:
        return 'Quick: a short test — aim for 5–10 questions, about 10 minutes.';
      case TestKind.sectional:
        return 'Sectional: cover several subjects/topics via the Syllabus step.';
      case TestKind.challengeWithFriends:
        return 'Share the join code so friends can take it with you.';
      case TestKind.group:
        return 'Visible to members of the group you select.';
      case TestKind.self:
      case TestKind.adaptive:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Basic Details',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Enter the basic information for your test.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  )),
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
          DropdownButtonFormField<TestKind>(
            initialValue: kind,
            decoration: InputDecoration(
              labelText: 'Test Type',
              helperText: hintFor(kind),
              helperMaxLines: 3,
            ),
            items: [
              for (final k in TestKind.creatable)
                DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (k) {
              if (k != null) onKindChanged(k);
            },
          ),
        ],
      ),
    );
  }
}
