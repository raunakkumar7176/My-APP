import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/theme_service.dart';

/// Settings: theme (persisted via [ThemeService]), and shortcuts to the
/// other preference surfaces that already exist elsewhere in the app
/// (per-group notification mute lives on each group; routine preferences
/// live in the Routine feature; account editing is the existing Profile
/// screen). Nothing here duplicates that state — it only links to it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel(context, 'Appearance'),
          const _ThemeCard(),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Preferences'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Routine Preferences'),
                  subtitle: const Text('Manage your study routine'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/routine'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: const Text('Configure notification preferences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notification-settings'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: const Text('Notification Center'),
                  subtitle: const Text('View all your notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notifications'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('My Uploaded Documents'),
                  subtitle: const Text(
                    'Manage files uploaded for test creation',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/my-uploads'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Account'),
                  subtitle: const Text('Name, bio, exam targets'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/profile'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('Privacy'),
                  subtitle: Text(
                    'Your data is scoped to your account and groups',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'About'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About & Founder Desk'),
              subtitle: const Text(
                'Vision, founder message & student help desk',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/about'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final mode = ThemeService.instance.mode;
        return Card(
          child: Column(
            children: [
              _tile(
                context,
                ThemeMode.light,
                'Light',
                Icons.light_mode_outlined,
                mode,
              ),
              const Divider(height: 1),
              _tile(
                context,
                ThemeMode.dark,
                'Dark',
                Icons.dark_mode_outlined,
                mode,
              ),
              const Divider(height: 1),
              _tile(
                context,
                ThemeMode.system,
                'System',
                Icons.brightness_auto_outlined,
                mode,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    ThemeMode value,
    String label,
    IconData icon,
    ThemeMode current,
  ) {
    return RadioListTile<ThemeMode>(
      value: value,
      groupValue: current,
      secondary: Icon(icon),
      title: Text(label),
      onChanged: (m) {
        if (m != null) ThemeService.instance.setMode(m);
      },
    );
  }
}
