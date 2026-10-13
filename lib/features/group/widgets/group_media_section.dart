import 'package:flutter/material.dart';

/// "Media & Files" — no shared-file feature exists in this group yet (no
/// storage bucket, no table). An honest empty state, not a fabricated list.
class GroupMediaSection extends StatelessWidget {
  const GroupMediaSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Media & Files', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          key: const Key('group_media_empty'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Shared files are coming soon.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
