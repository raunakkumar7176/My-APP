import 'package:flutter/material.dart';

import '../../../core/services/push_notification_service.dart';
import '../state/notification_settings_controller.dart';

/// Notification preferences screen. Allows the user to configure:
/// - Master notifications toggle
/// - Per-category toggles
/// - Quiet hours
/// - Push notifications: Android permission status + the app-level
///   `push_enabled` toggle, kept honestly in sync with each other (Phase
///   14 — never claims push is on when the OS permission is actually off)
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({this.controller, this.pushGateway, super.key});

  final NotificationSettingsController? controller;

  /// Injection point for tests; production defaults to the real
  /// Firebase/permission_handler-backed singleton.
  final PushPermissionGateway? pushGateway;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController _controller;
  late final bool _owns;
  late final PushPermissionGateway _push;

  SystemPermissionStatus? _permissionStatus;
  bool _checkingPermission = false;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _controller = widget.controller ?? NotificationSettingsController();
    _push = widget.pushGateway ?? PushNotificationService.instance;
    _controller.addListener(_onChanged);
    _controller.load();
    _refreshPermissionStatus();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPermissionStatus() async {
    final status = await _push.checkPermissionStatus();
    if (mounted) setState(() => _permissionStatus = status);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_owns) _controller.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _toggleMaster(bool value) async {
    final ok = await _controller.updateSetting(notificationsEnabled: value);
    if (!mounted) return;
    if (!ok) _snack(_controller.error ?? 'Could not update setting.', error: true);
  }

  Future<void> _toggleCategory({
    required String category,
    required bool value,
  }) async {
    bool? ok;
    switch (category) {
      case 'test_reminders':
        ok = await _controller.updateSetting(testReminders: value);
      case 'live_test_invitations':
        ok = await _controller.updateSetting(liveTestInvitations: value);
      case 'test_results':
        ok = await _controller.updateSetting(testResults: value);
      case 'group_announcements':
        ok = await _controller.updateSetting(groupAnnouncements: value);
      case 'group_messages':
        ok = await _controller.updateSetting(groupMessages: value);
      case 'routine_reminders':
        ok = await _controller.updateSetting(routineReminders: value);
      case 'ai_reports':
        ok = await _controller.updateSetting(aiReports: value);
      case 'system_updates':
        ok = await _controller.updateSetting(systemUpdates: value);
      case 'test_invitations':
        ok = await _controller.updateSetting(testInvitations: value);
    }
    if (!mounted) return;
    if (ok != true) _snack(_controller.error ?? 'Could not update setting.', error: true);
  }

  Future<void> _handleEnablePush() async {
    setState(() => _checkingPermission = true);
    final status = await _push.requestPermissionWithRationale(context);
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _checkingPermission = false;
    });

    if (status == SystemPermissionStatus.granted) {
      await _push.registerCurrentDevice();
      if (!mounted) return;
      final ok = await _controller.updateSetting(pushEnabled: true);
      if (!mounted) return;
      if (!ok) _snack(_controller.error ?? 'Could not update setting.', error: true);
    }
    // Denied/permanently-denied: leave push_enabled as-is (still false by
    // default) — the UI below shows the real reason, never a false "on".
  }

  Future<void> _togglePushEnabled(bool value) async {
    if (value) {
      await _handleEnablePush();
      return;
    }
    final ok = await _controller.updateSetting(pushEnabled: false);
    if (!mounted) return;
    if (!ok) _snack(_controller.error ?? 'Could not update setting.', error: true);
  }

  Future<void> _toggleQuietHours(bool value) async {
    final ok = await _controller.updateSetting(quietHoursEnabled: value);
    if (!mounted) return;
    if (!ok) _snack(_controller.error ?? 'Could not update setting.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.error != null && _controller.settings == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_controller.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _controller.load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final settings = _controller.settings;
    if (settings == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel('Master'),
        Card(
          child: SwitchListTile(
            key: const Key('master_toggle'),
            title: const Text('Enable Notifications'),
            subtitle: const Text('Turn off to disable all in-app notifications'),
            value: settings.notificationsEnabled,
            onChanged: _controller.isSaving ? null : _toggleMaster,
          ),
        ),
        if (!_controller.isMasterOff) ...[
          const SizedBox(height: 24),
          _sectionLabel('Push Notifications'),
          _buildPushSection(settings.pushEnabled),
          const SizedBox(height: 24),
          _sectionLabel('Categories'),
          Card(
            child: Column(
              children: [
                _toggleTile(
                  key: const Key('toggle_group_messages'),
                  icon: Icons.chat_bubble_outline,
                  title: 'Group Chat',
                  subtitle: 'New messages in groups',
                  value: settings.groupMessages,
                  category: 'group_messages',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_group_announcements'),
                  icon: Icons.campaign_outlined,
                  title: 'Announcements',
                  subtitle: 'Group announcements',
                  value: settings.groupAnnouncements,
                  category: 'group_announcements',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_test_invitations'),
                  icon: Icons.quiz_outlined,
                  title: 'Test Invitations',
                  subtitle: 'New tests in your groups',
                  value: settings.testInvitations,
                  category: 'test_invitations',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_test_reminders'),
                  icon: Icons.alarm_outlined,
                  title: 'Test Reminders',
                  subtitle: 'Upcoming test reminders',
                  value: settings.testReminders,
                  category: 'test_reminders',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_test_results'),
                  icon: Icons.assessment_outlined,
                  title: 'Results',
                  subtitle: 'Test results and scores',
                  value: settings.testResults,
                  category: 'test_results',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_routine_reminders'),
                  icon: Icons.schedule_outlined,
                  title: 'Routine & Study',
                  subtitle: 'Study session reminders',
                  value: settings.routineReminders,
                  category: 'routine_reminders',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_ai_reports'),
                  icon: Icons.insights_outlined,
                  title: 'AI Reports',
                  subtitle: 'AI generation and coach reports',
                  value: settings.aiReports,
                  category: 'ai_reports',
                ),
                _divider,
                _toggleTile(
                  key: const Key('toggle_system_updates'),
                  icon: Icons.info_outline,
                  title: 'System',
                  subtitle: 'Important system notifications',
                  value: settings.systemUpdates,
                  category: 'system_updates',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel('Quiet Hours'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('toggle_quiet_hours'),
                  title: const Text('Quiet Hours'),
                  subtitle: Text(
                    settings.quietHoursEnabled
                        ? '${settings.quietFrom} - ${settings.quietTo}'
                        : 'Disabled',
                  ),
                  value: settings.quietHoursEnabled,
                  onChanged: _controller.isSaving ? null : _toggleQuietHours,
                ),
                if (settings.quietHoursEnabled) ...[
                  _divider,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'High priority notifications (security, test starting) bypass quiet hours.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildPushSection(bool pushEnabled) {
    final status = _permissionStatus;
    final theme = Theme.of(context);

    final (statusText, statusIcon, statusColor) = switch (status) {
      SystemPermissionStatus.granted => (
          'Notifications enabled',
          Icons.check_circle_outline,
          theme.colorScheme.primary,
        ),
      SystemPermissionStatus.denied => (
          'Permission required',
          Icons.notifications_off_outlined,
          theme.colorScheme.error,
        ),
      SystemPermissionStatus.permanentlyDenied => (
          'Notifications disabled in Android Settings',
          Icons.notifications_off_outlined,
          theme.colorScheme.error,
        ),
      _ => ('Checking…', Icons.hourglass_empty, theme.colorScheme.onSurfaceVariant),
    };

    return Card(
      child: Column(
        children: [
          ListTile(
            key: const Key('push_permission_status'),
            leading: Icon(statusIcon, color: statusColor),
            title: const Text('Android Permission'),
            subtitle: Text(statusText, style: TextStyle(color: statusColor)),
            trailing: status == SystemPermissionStatus.permanentlyDenied
                ? TextButton(
                    key: const Key('open_android_settings_button'),
                    onPressed: _push.openAndroidNotificationSettings,
                    child: const Text('Open Settings'),
                  )
                : null,
          ),
          _divider,
          SwitchListTile(
            key: const Key('push_enabled_toggle'),
            title: const Text('Push Notifications'),
            subtitle: Text(
              status == SystemPermissionStatus.permanentlyDenied
                  ? 'Enable notifications for this app in Android Settings first'
                  : 'Get a phone notification even when the app is closed',
            ),
            value: pushEnabled && status == SystemPermissionStatus.granted,
            onChanged: (_controller.isSaving || _checkingPermission)
                ? null
                : status == SystemPermissionStatus.permanentlyDenied
                    ? null
                    : _togglePushEnabled,
          ),
        ],
      ),
    );
  }

  Widget _toggleTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required String category,
  }) {
    return SwitchListTile(
      key: key,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _controller.isSaving
          ? null
          : (v) => _toggleCategory(category: category, value: v),
    );
  }

  Widget _sectionLabel(String text) {
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

  static const _divider = Divider(height: 1);
}
