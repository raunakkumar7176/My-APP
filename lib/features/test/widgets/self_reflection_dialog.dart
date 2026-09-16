import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/self_reflection.dart';

class SelfReflectionDialog extends StatefulWidget {
  const SelfReflectionDialog({super.key});

  static Future<SelfReflection?> show(BuildContext context) {
    return showDialog<SelfReflection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SelfReflectionDialog(),
    );
  }

  @override
  State<SelfReflectionDialog> createState() => _SelfReflectionDialogState();
}

class _SelfReflectionDialogState extends State<SelfReflectionDialog> {
  ConfidenceLevel? _confidence;
  ExpectedPerformance? _expected;
  final _reflectionController = TextEditingController();

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  bool get _isValid => _confidence != null && _expected != null;

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop(SelfReflection(
      confidence: _confidence!,
      expectedPerformance: _expected!,
      optionalReflection: _reflectionController.text.trim().isEmpty
          ? null
          : _reflectionController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Before You Submit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How confident are you about your performance?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ConfidenceLevel.values.map((level) {
                final selected = _confidence == level;
                final label = SelfReflection(
                  confidence: level,
                  expectedPerformance: ExpectedPerformance.below40,
                ).confidenceLabel;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _confidence = level),
                  selectedColor:
                      AppColors.primaryLight.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected
                        ? AppColors.primaryLight
                        : AppColors.textPrimaryLight,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'What score range do you expect?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ExpectedPerformance.values.map((perf) {
                final selected = _expected == perf;
                final label = SelfReflection(
                  confidence: ConfidenceLevel.medium,
                  expectedPerformance: perf,
                ).expectedRangeLabel;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _expected = perf),
                  selectedColor:
                      AppColors.primaryLight.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected
                        ? AppColors.primaryLight
                        : AppColors.textPrimaryLight,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Any thoughts? (optional)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reflectionController,
              decoration: InputDecoration(
                hintText: 'e.g. Found section X tricky...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _isValid ? _submit : null,
          child: const Text('Submit Test'),
        ),
      ],
    );
  }
}
