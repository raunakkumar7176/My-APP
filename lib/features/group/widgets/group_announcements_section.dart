import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_announcement.dart';
import '../state/group_hub_controller.dart';

/// Announcements section in the group hub. Every member sees the list
/// (newest first, as the server returns it); callers whose server-reported
/// SEND_ANNOUNCEMENT permission (or owner, via the function's own bypass) is
/// true also see Post / Edit / Delete. The live RLS on
/// `group_announcements` is the boundary; UI visibility is UX only.
class GroupAnnouncementsSection extends StatelessWidget {
  const GroupAnnouncementsSection({required this.controller, super.key});

  final GroupHubController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return Column(
      key: const Key('group_announcements_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Announcements', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (c.announcements.isNotEmpty)
              Text(
                '${c.announcements.length}',
                key: const Key('announcements_count'),
                style: theme.textTheme.bodySmall,
              ),
            const Spacer(),
            if (c.canSendAnnouncement)
              TextButton.icon(
                key: const Key('add_announcement_button'),
                onPressed: c.announcementSaving
                    ? null
                    : () => _compose(context, null),
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Post'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.announcementsLoading &&
            c.announcements.isEmpty &&
            c.announcementsError == null)
          const LinearProgressIndicator(key: Key('announcements_loading'))
        else if (c.announcementsError != null && c.announcements.isEmpty)
          Row(
            key: const Key('announcements_error'),
            children: [
              Expanded(
                child: Text(
                  c.announcementsError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('announcements_retry'),
                onPressed: c.announcementSaving ? null : c.retryAnnouncements,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (c.announcements.isEmpty)
          Text(
            'No announcements yet.',
            key: const Key('announcements_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final a in c.announcements) _card(context, a),
        if (c.announcementsError != null && c.announcements.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              c.announcementsError!,
              key: const Key('announcements_action_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, GroupAnnouncement a) {
    final c = controller;
    final theme = Theme.of(context);
    final acting = c.actingAnnouncementId == a.id;
    final disabled = acting || c.announcementSaving;
    final author = c.announcementAuthorLabel(a);
    final meta = [
      ?author,
      _when(a.createdAt),
      if (a.wasEdited) 'edited',
    ].join(' · ');
    return Card(
      key: Key('announcement_${a.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(a.body),
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    key: Key('announcement_meta_${a.id}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (c.canSendAnnouncement) ...[
              IconButton(
                key: Key('edit_announcement_${a.id}'),
                tooltip: 'Edit announcement',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: disabled ? null : () => _compose(context, a),
              ),
              IconButton(
                key: Key('delete_announcement_${a.id}'),
                tooltip: 'Delete announcement',
                icon: acting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 20),
                onPressed: disabled ? null : () => _delete(context, a),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// One dialog for post (null) and edit. Validation happens in the
  /// controller so the same rule applies to every caller.
  Future<void> _compose(BuildContext context, GroupAnnouncement? existing) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    final editing = existing != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing ? 'Edit announcement' : 'New announcement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('announcement_title_field'),
                controller: titleCtrl,
                maxLength: GroupAnnouncement.maxTitleLength,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('announcement_body_field'),
                controller: bodyCtrl,
                minLines: 3,
                maxLines: 6,
                maxLength: GroupAnnouncement.maxBodyLength,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key(editing ? 'confirm_edit_announcement' : 'confirm_post_announcement'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(editing ? 'Save' : 'Post'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = editing
        ? await controller.updateAnnouncement(
            existing,
            title: titleCtrl.text,
            body: bodyCtrl.text,
          )
        : await controller.createAnnouncement(
            title: titleCtrl.text,
            body: bodyCtrl.text,
          );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? (editing ? 'Announcement updated.' : 'Announcement posted.')
              : (controller.error ?? 'Could not save the announcement.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }

  Future<void> _delete(BuildContext context, GroupAnnouncement a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('"${a.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_announcement'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = await controller.deleteAnnouncement(a);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Announcement deleted.'
              : (controller.error ?? 'Could not delete the announcement.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }
}
