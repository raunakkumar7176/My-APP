import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/models/profile.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_service.dart';

/// App-wide navigation drawer. Reuses [ProfileService] for the header and
/// existing named routes for every destination — no new navigation state.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.currentProfile;
    final email = AuthService.currentUser?.email;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _Header(profile: profile, email: email),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _item(
                    context,
                    icon: Icons.dashboard_outlined,
                    label: 'Dashboard',
                    onTap: () => context.go('/home'),
                  ),
                  _item(
                    context,
                    icon: Icons.person_outline,
                    label: 'Profile',
                    onTap: () => context.push('/profile'),
                  ),
                  const Divider(height: 1),
                  _item(
                    context,
                    icon: Icons.calendar_today_outlined,
                    label: 'My Routine',
                    onTap: () => context.push('/routine'),
                  ),
                  _item(
                    context,
                    icon: Icons.menu_book_outlined,
                    label: 'Study',
                    onTap: () => context.push('/study'),
                  ),
                  _item(
                    context,
                    icon: Icons.event_note_outlined,
                    label: 'Calendar',
                    onTap: () => context.push('/calendar'),
                  ),
                  const Divider(height: 1),
                  _item(
                    context,
                    icon: Icons.quiz_outlined,
                    label: 'My Tests',
                    onTap: () => context.push('/tests'),
                  ),
                  _item(
                    context,
                    icon: Icons.drafts_outlined,
                    label: 'My Drafts',
                    onTap: () => context.push('/tests/drafts'),
                  ),
                  _item(
                    context,
                    icon: Icons.library_books_outlined,
                    label: 'Question Bank',
                    onTap: () => context.push('/question-bank'),
                  ),
                  const Divider(height: 1),
                  _item(
                    context,
                    icon: Icons.groups_outlined,
                    label: 'Groups',
                    onTap: () => context.push('/groups'),
                  ),
                  _item(
                    context,
                    icon: Icons.insights_outlined,
                    label: 'Performance',
                    onTap: () => context.push('/performance'),
                  ),
                  _item(
                    context,
                    icon: Icons.leaderboard_outlined,
                    label: 'Leaderboard',
                    onTap: () => context.push('/leaderboard'),
                  ),
                  const Divider(height: 1),
                  _item(
                    context,
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () => context.push('/notifications'),
                  ),
                  _item(
                    context,
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => context.push('/settings'),
                  ),
                  _item(
                    context,
                    icon: Icons.help_outline,
                    label: 'Help / About',
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _item(
              context,
              icon: Icons.logout,
              label: 'Logout',
              color: AppColors.error,
              onTap: () async {
                final shouldLogout = await _showLogoutConfirmation(context);
                if (shouldLogout != true) return;
                try {
                  await AuthService.signOut();
                } on Exception catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString().replaceFirst('AppError: ', ''),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: color != null ? TextStyle(color: color) : null),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }
}

Future<bool> _showLogoutConfirmation(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you want to Log out'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    ) ?? false;
  }

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.email});

  final Profile? profile;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.onPrimary.withValues(
              alpha: 0.15,
            ),
            child: Text(
              profile?.initials ?? '?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile?.displayName ?? 'Student',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (email != null) ...[
            const SizedBox(height: 2),
            Text(
              email!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
