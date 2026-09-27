import 'package:flutter/material.dart';

import '../../../core/models/academic_special_day.dart';

/// Full detail sheet for one [AcademicSpecialDay] — significance, and a
/// couple of quick exam-revision bullet points when the row has them. Shown
/// from both the Dashboard greeting pill and the Calendar's day banner.
class SpecialDayBottomSheet extends StatelessWidget {
  const SpecialDayBottomSheet({required this.day, super.key});

  final AcademicSpecialDay day;

  static Future<void> show(BuildContext context, AcademicSpecialDay day) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SpecialDayBottomSheet(day: day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    day.title,
                    key: const Key('special_day_sheet_title'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(day.categoryLabel, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 16),
            Text('History & Significance', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(day.significance, style: theme.textTheme.bodyMedium),
            if (day.examNotes != null && day.examNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Exam Relevance', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(day.examNotes!, key: const Key('special_day_sheet_exam_notes'), style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
