import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../feedback/presentation/feedback_dialog.dart';

/// Unified Settings Section Card wrapper with rounded corners (16.0),
/// subtle border, and elevation.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF334155).withValues(alpha: 0.8)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

/// Comprehensive, modern Settings Screen for "My Preparation".
/// Provides persistent preferences, profile snapshot, study targets,
/// sensory toggles, notification reminders, privacy controls, and help desk.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StreamSubscription<ProfileStatus>? _profileSub;

  // Persisted Preference States
  String _targetExam = 'UPSC CSE 2026';
  String _dailyGoal = '45 Mins / Day • 3 Tests Target';
  String _language = 'English (US)';

  bool _hapticFeedback = true;
  bool _soundEffects = true;

  String _revisionReminder = '07:00 AM';

  String _groupInvites = 'Anyone';
  bool _showAgeBadge = true;

  /// Real installed version, from `package_info_plus` — never the old
  /// hardcoded "v1.2.0 (Build 58)" string, which was stale/fabricated.
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadPersistedSettings();
    _listenToProfile();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version} (Build ${info.buildNumber})');
      }
    } catch (_) {
      // Leave null — the UI shows nothing rather than a fabricated version.
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  void _listenToProfile() {
    _profileSub = ProfileService.statusStream.listen((_) {
      if (!mounted) return;
      setState(() {
        final profile = ProfileService.currentProfile;
        if (profile != null) {
          _showAgeBadge = profile.showAgeBadge;
          final serverExam = profile.examTargets.firstOrNull;
          if (serverExam != null) _targetExam = serverExam;
          _groupInvites = _groupInvitePolicyLabel(profile.groupInvitePolicy);
        }
      });
    });
    if (ProfileService.currentProfile == null &&
        SupabaseService.isInitialized) {
      ProfileService.loadProfile();
    }
  }

  Future<void> _loadPersistedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        // The real server value (profiles.exam_targets) wins whenever it's
        // set — the local pref is only a fallback for the brief window
        // before the profile has loaded, never allowed to shadow it.
        _targetExam =
            ProfileService.currentProfile?.examTargets.firstOrNull ??
            prefs.getString('settings_target_exam') ??
            'UPSC CSE 2026';
        _dailyGoal =
            prefs.getString('settings_daily_study_goal') ??
            '45 Mins / Day • 3 Tests Target';
        _language =
            prefs.getString('settings_language_medium') ?? 'English (US)';
        _hapticFeedback = prefs.getBool('settings_haptic_feedback') ?? true;
        _soundEffects = prefs.getBool('settings_sound_effects') ?? true;
        _revisionReminder =
            prefs.getString('settings_revision_reminder') ?? '07:00 AM';
        // Real, server-enforced field (profiles.group_invite_policy, 0085).
        final serverPolicy = ProfileService.currentProfile?.groupInvitePolicy;
        _groupInvites = serverPolicy != null
            ? _groupInvitePolicyLabel(serverPolicy)
            : (prefs.getString('settings_group_invites') ?? 'Anyone');
        // Real, peer-visible preference (profiles.show_age_badge, 0084) —
        // the server row is the source of truth, not the device.
        _showAgeBadge = ProfileService.currentProfile?.showAgeBadge ?? true;
      });
    } catch (_) {
      // SharedPreferences failure fallback to defaults
    }
  }

  Future<void> _saveString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  void _triggerHapticIfEnabled() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  // ── Bottom Sheet Modals for Choices ──

  Future<void> _showTargetExamModal() async {
    final exams = [
      'UPSC CSE 2026',
      'SSC CGL',
      'NEET UG',
      'JEE Advanced',
      'GATE 2026',
      'State PSC',
      'Banking / IBPS',
      'NDA / CDS',
    ];

    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _buildSelectionSheet(
        ctx,
        title: 'Select Target Exam',
        options: exams,
        selected: _targetExam,
      ),
    );

    if (picked != null && picked != _targetExam) {
      _triggerHapticIfEnabled();
      setState(() => _targetExam = picked);
      _saveString('settings_target_exam', picked);
      // Real, server-side field (profiles.exam_targets) — used elsewhere in
      // the app for content targeting, not just a locally-cached label.
      try {
        await ProfileService.updateProfile(examTargets: [picked]);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e is AppError ? e.message : 'Could not save your target exam.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDailyGoalModal() async {
    final goals = [
      '30 Mins / Day • 2 Tests Target',
      '45 Mins / Day • 3 Tests Target',
      '60 Mins / Day • 4 Tests Target',
      '90 Mins / Day • 6 Tests Target',
      '120 Mins / Day • 8 Tests Target',
    ];

    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _buildSelectionSheet(
        ctx,
        title: 'Daily Study Goal',
        options: goals,
        selected: _dailyGoal,
      ),
    );

    if (picked != null && picked != _dailyGoal) {
      _triggerHapticIfEnabled();
      setState(() => _dailyGoal = picked);
      _saveString('settings_daily_study_goal', picked);
    }
  }

  Future<void> _showLanguageModal() async {
    final languages = [
      'English (US)',
      'Hindi (हिन्दी)',
      'Bilingual (Hinglish)',
    ];

    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _buildSelectionSheet(
        ctx,
        title: 'Language & Medium',
        options: languages,
        selected: _language,
      ),
    );

    if (picked != null && picked != _language) {
      _triggerHapticIfEnabled();
      setState(() => _language = picked);
      _saveString('settings_language_medium', picked);

      // Real locale switch (LocaleService + generated AppLocalizations) —
      // English and Hindi genuinely change the app's UI text now.
      // "Bilingual (Hinglish)" is not a real distinct locale (there's no
      // such ICU language tag to translate into) — it maps to Hindi, and
      // that's disclosed below rather than silently treated as English.
      final isHindiFamily = picked != 'English (US)';
      await LocaleService.instance.setLocale(
        isHindiFamily ? const Locale('hi') : const Locale('en'),
      );

      // Coverage is real but partial: Settings and the Dashboard are
      // translated; most other screens aren't yet — say so rather than
      // implying full app coverage.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              picked == 'Bilingual (Hinglish)'
                  ? 'Switched to Hindi (a dedicated Hinglish mode isn\'t built yet). '
                      'Settings and Home are translated; other screens are still English.'
                  : isHindiFamily
                      ? 'भाषा बदल दी गई। Settings और Home अनुवादित हैं; बाकी स्क्रीन अभी अंग्रेज़ी में हैं।'
                      : 'Language switched. Settings and Home are translated; other screens are still being localized.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _showGroupInvitesModal() async {
    final options = ['Anyone', 'Only Following', 'None'];

    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _buildSelectionSheet(
        ctx,
        title: 'Who Can Invite You to Groups',
        options: options,
        selected: _groupInvites,
      ),
    );

    if (picked != null && picked != _groupInvites) {
      _triggerHapticIfEnabled();
      setState(() => _groupInvites = picked);
      _saveString('settings_group_invites', picked);
      // Real, server-enforced field (profiles.group_invite_policy, 0085) —
      // the group_invitations INSERT policy itself checks this now, not
      // just a client-side label.
      try {
        await ProfileService.updateProfile(groupInvitePolicy: _groupInvitePolicyDb(picked));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved.'), duration: Duration(seconds: 2)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e is AppError ? e.message : 'Could not save this setting.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  static String _groupInvitePolicyDb(String label) => switch (label) {
        'Only Following' => 'only_following',
        'None' => 'none',
        _ => 'anyone',
      };

  static String _groupInvitePolicyLabel(String db) => switch (db) {
        'only_following' => 'Only Following',
        'none' => 'None',
        _ => 'Anyone',
      };

  Future<void> _pickRevisionReminderTime() async {
    TimeOfDay initial = const TimeOfDay(hour: 7, minute: 0);
    try {
      final parts = _revisionReminder.split(' ');
      final timeParts = parts[0].split(':');
      var hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && hour < 12) {
        hour += 12;
      }
      initial = TimeOfDay(hour: hour, minute: minute);
    } catch (_) {}

    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked != null && mounted) {
      _triggerHapticIfEnabled();
      final formatted = picked.format(context);
      setState(() => _revisionReminder = formatted);
      _saveString('settings_revision_reminder', formatted);

      // Actually schedule a real local notification for the next occurrence
      // of this time (today if still ahead, else tomorrow) — previously
      // this only saved a label and claimed "scheduled" with nothing behind
      // it. Fixed id so re-picking a new time replaces the same alarm
      // rather than stacking duplicates.
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      final scheduled = await PushNotificationService.instance.scheduleExactNotification(
        id: _revisionReminderNotificationId,
        title: 'Revision Reminder',
        body: 'Time for your daily revision — keep the streak going!',
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        payload: '/study',
        matchDateTimeComponents: DateTimeComponents.time,
      );
      final message = scheduled
          ? 'Revision reminder set for $formatted, every day.'
          : 'Time saved, but the reminder could not be scheduled. '
              'Check notification permission in Settings.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  /// Fixed local-notification id for the daily revision reminder — reusing
  /// it means picking a new time replaces the existing alarm instead of
  /// scheduling a second one alongside it.
  static const _revisionReminderNotificationId = 900001;

  Widget _buildSelectionSheet(
    BuildContext ctx, {
    required String title,
    required List<String> options,
    required String selected,
  }) {
    final theme = Theme.of(ctx);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            ...options.map((option) {
              final isChosen = option == selected;
              return ListTile(
                title: Text(
                  option,
                  style: TextStyle(
                    fontWeight: isChosen ? FontWeight.bold : FontWeight.normal,
                    color: isChosen ? theme.colorScheme.primary : null,
                  ),
                ),
                trailing: isChosen
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(option),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Password Change Dialog ──
  void _showPasswordSecurityDialog() {
    final email = AuthService.currentUser?.email ?? 'your account email';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Security & Password'),
          ],
        ),
        content: Text(
          'A secure password reset link will be sent to $email.\n\nFollow the instructions in the email to update your credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (SupabaseService.isInitialized) {
                try {
                  final userEmail = AuthService.currentUser?.email;
                  if (userEmail != null) {
                    await SupabaseService.client.auth.resetPasswordForEmail(
                      userEmail,
                      redirectTo: AuthService.emailVerificationRedirectUrl,
                    );
                  }
                } catch (_) {}
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset link sent to your email.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }

  // ── Cache Clearing ──
  /// Actually clears Flutter's real in-memory/disk image cache — the only
  /// cache this app keeps that's safe and meaningful to clear from a
  /// button. Previously this just reset a fabricated "34.2 MB" label in
  /// SharedPreferences to "0.0 MB" without touching anything real.
  Future<void> _clearOfflineCache() async {
    _triggerHapticIfEnabled();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image cache cleared.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Account Deletion Request ──
  /// Records a REAL request via `rpc_request_account_deletion` (0084) into
  /// `account_deletion_requests`, reviewed by the app owner — this never
  /// auto-deletes anything (that stays a deliberate manual/admin action,
  /// not an unattended timer) and never claims an email was sent, since no
  /// email is actually triggered.
  void _showDeleteAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Account Deletion'),
        content: const Text(
          'Are you sure you want to request account deletion?\n\n'
          'Your request will be recorded and reviewed by our team, who will '
          'contact you to complete the process. This does not delete your '
          'account immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ProfileService.requestAccountDeletion();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Your deletion request has been recorded.'),
                      backgroundColor: AppColors.error,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e is AppError ? e.message : 'Could not submit your request. Please try again.',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
  }

  // ── Log Out Dialog ──
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out of My Preparation?'),
        content: const Text(
          'You will need to sign in again to access your cohort, tests, and study progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await AuthService.signOut();
      } catch (_) {}
      if (mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _launchUrlStr(String urlStr) async {
    final uri = Uri.tryParse(urlStr);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profile = ProfileService.currentProfile;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle), centerTitle: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header: Compact Profile & Role Card
                _buildProfileHeaderCard(profile, isDark, theme),

                const SizedBox(height: 24),

                // 2. Group 1: Study & Exam Targets
                SettingsSectionCard(
                  title: l10n.settingsSectionExam,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.school_outlined,
                        color: Color(0xFF2563EB),
                      ),
                      title: Text(l10n.settingsTargetExam),
                      subtitle: Text(_targetExam),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showTargetExamModal,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.timer_outlined,
                        color: Color(0xFFD97706),
                      ),
                      title: Text(l10n.settingsDailyGoal),
                      subtitle: Text(_dailyGoal),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showDailyGoalModal,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.translate_rounded,
                        color: Color(0xFF10B981),
                      ),
                      title: Text(l10n.settingsLanguage),
                      subtitle: Text(_language),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showLanguageModal,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 3. Group 2: Appearance & Sensory
                SettingsSectionCard(
                  title: l10n.settingsSectionDisplay,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.palette_outlined,
                        color: Color(0xFF7C3AED),
                      ),
                      title: Text(l10n.settingsThemeMode),
                      subtitle: Text(
                        _themeModeName(ThemeService.instance.mode),
                      ),
                      trailing: _buildThemeSegmentedButton(theme),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: const Icon(
                        Icons.vibration_rounded,
                        color: Color(0xFF0284C7),
                      ),
                      title: Text(l10n.settingsHaptic),
                      subtitle: Text(
                        l10n.settingsHapticSubtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _hapticFeedback,
                      onChanged: (val) {
                        setState(() => _hapticFeedback = val);
                        _saveBool('settings_haptic_feedback', val);
                        if (val) HapticFeedback.lightImpact();
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: const Icon(
                        Icons.volume_up_outlined,
                        color: Color(0xFFF59E0B),
                      ),
                      title: Text(l10n.settingsSoundEffects),
                      subtitle: Text(
                        l10n.settingsSoundEffectsSubtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _soundEffects,
                      onChanged: (val) {
                        setState(() => _soundEffects = val);
                        _saveBool('settings_sound_effects', val);
                        _triggerHapticIfEnabled();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 4. Group 3: Notifications & Reminders
                SettingsSectionCard(
                  title: l10n.settingsSectionNudges,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.alarm_on_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      title: Text(l10n.settingsRevisionReminder),
                      subtitle: Text(
                        l10n.settingsRevisionReminderSubtitle(_revisionReminder),
                      ),
                      trailing: const Icon(Icons.access_time_rounded),
                      onTap: _pickRevisionReminderTime,
                    ),
                    const Divider(height: 1),
                    // Real, server-backed per-category push preferences
                    // (notification_settings table) live on their own
                    // screen — this used to duplicate two of those
                    // categories as local-only toggles that had no effect
                    // on which pushes the server actually sent.
                    ListTile(
                      leading: const Icon(
                        Icons.notifications_active_outlined,
                        color: Color(0xFFD97706),
                      ),
                      title: Text(l10n.settingsPushPreferences),
                      subtitle: Text(
                        l10n.settingsPushPreferencesSubtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/notification-settings'),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 5. Group 4: Privacy & Security
                SettingsSectionCard(
                  title: l10n.settingsSectionPrivacy,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.group_add_outlined,
                        color: Color(0xFF0284C7),
                      ),
                      title: Text(l10n.settingsGroupInvites),
                      subtitle: Text(_groupInvites),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showGroupInvitesModal,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: const Icon(
                        Icons.cake_outlined,
                        color: Color(0xFFE11D48),
                      ),
                      title: Text(l10n.settingsShowAgeBadge),
                      subtitle: Text(
                        l10n.settingsShowAgeBadgeSubtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _showAgeBadge,
                      onChanged: (val) async {
                        setState(() => _showAgeBadge = val);
                        _triggerHapticIfEnabled();
                        // Real, peer-visible server field (0084) — not just
                        // a local device flag; ProfileScreen's Age display
                        // for other viewers reads this directly.
                        try {
                          await ProfileService.updateProfile(showAgeBadge: val);
                        } catch (e) {
                          if (mounted) {
                            setState(() => _showAgeBadge = !val);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is AppError ? e.message : 'Could not save this setting.',
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFF7C3AED),
                      ),
                      title: Text(l10n.settingsChangePassword),
                      subtitle: Text(l10n.settingsChangePasswordSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showPasswordSecurityDialog,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 6. Group 5: Support, Legal & About
                SettingsSectionCard(
                  title: l10n.settingsSectionAbout,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFD97706),
                      ),
                      title: Text(l10n.settingsAboutApp),
                      subtitle: Text(l10n.settingsAboutAppSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/about'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.support_agent_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      title: Text(l10n.settingsHelpDesk),
                      subtitle: Text(l10n.settingsHelpDeskSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => const FeedbackDialog(),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.cleaning_services_outlined,
                        color: Color(0xFF10B981),
                      ),
                      title: Text(l10n.settingsClearCache),
                      subtitle: Text(l10n.settingsClearCacheSubtitle),
                      trailing: TextButton(
                        onPressed: _clearOfflineCache,
                        child: Text(l10n.settingsClear),
                      ),
                      onTap: _clearOfflineCache,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.policy_outlined,
                        color: Color(0xFF64748B),
                      ),
                      title: Text(l10n.settingsTerms),
                      subtitle: Text(l10n.settingsTermsSubtitle),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () =>
                          _launchUrlStr('https://mypreparation.app/privacy'),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // 7. Footer: Danger Zone & Session
                Center(
                  child: Column(
                    children: [
                      // Version badge with official verified tick
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            // Real installed version (package_info_plus) —
                            // never the old hardcoded, stale "v1.2.0
                            // (Build 58)" string.
                            _appVersion == null
                                ? 'My Preparation'
                                : 'My Preparation v$_appVersion',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Log out button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _handleLogout,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: Text('🚪 ${l10n.settingsLogOut}'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Delete Account Text Link
                      TextButton(
                        onPressed: _showDeleteAccountDialog,
                        child: Text(
                          l10n.settingsRequestDeletion,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12.5,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeaderCard(
    Profile? profile,
    bool isDark,
    ThemeData theme,
  ) {
    final name = (profile != null && profile.fullName.trim().isNotEmpty)
        ? profile.fullName
        : 'Student Aspirant';
    final studentId = profile?.studentCode ?? 'MP-*****';
    final isOwner = profile?.appRole == AppRole.owner;
    final isScholar = profile?.verifiedBadge == true;

    final borderColor = isOwner
        ? const Color(0xFFF59E0B)
        : (isScholar ? const Color(0xFF2563EB) : Colors.transparent);

    String roleLabel = '📚 Aspirant';
    Color roleColor = const Color(0xFF64748B);
    if (isOwner) {
      roleLabel = '👑 Founder';
      roleColor = const Color(0xFFD97706);
    } else if (isScholar) {
      roleLabel = '⭐ Scholar';
      roleColor = const Color(0xFF2563EB);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 14,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Avatar with verified border
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2.5),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              backgroundImage:
                  profile?.avatarUrl != null &&
                      profile!.avatarUrl!.trim().isNotEmpty
                  ? NetworkImage(profile.avatarUrl!)
                  : null,
              child: profile?.avatarUrl == null || profile!.avatarUrl!.isEmpty
                  ? Text(
                      profile?.initials ?? 'S',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 14),

          // Center Info: Full Name, Student ID, Role Chip
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '🆔 $studentId',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: roleColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        roleLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: roleColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right: Edit Profile Button
          OutlinedButton(
            key: const Key('settings_edit_profile_button'),
            onPressed: () => context.push('/profile'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Edit Profile',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSegmentedButton(ThemeData theme) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final currentMode = ThemeService.instance.mode;
        return PopupMenuButton<ThemeMode>(
          initialValue: currentMode,
          tooltip: 'Select Theme',
          onSelected: (mode) {
            _triggerHapticIfEnabled();
            ThemeService.instance.setMode(mode);
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: ThemeMode.system,
              child: Row(
                children: [
                  Icon(Icons.brightness_auto_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('System Default'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: ThemeMode.light,
              child: Row(
                children: [
                  Icon(Icons.light_mode_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Light'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: ThemeMode.dark,
              child: Row(
                children: [
                  Icon(Icons.dark_mode_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('OLED Dark'),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _themeModeName(currentMode),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _themeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'OLED Dark';
    }
  }
}
