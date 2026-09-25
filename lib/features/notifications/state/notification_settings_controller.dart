import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/notification_settings.dart';
import '../data/notification_settings_repository.dart';

/// Controller for notification preferences screen. Reads and writes
/// the caller's `notification_settings` row.
class NotificationSettingsController extends DisposableNotifier {
  NotificationSettingsController({
    NotificationSettingsRepository? repository,
  }) : _repository =
            repository ?? const SupabaseNotificationSettingsRepository();

  final NotificationSettingsRepository _repository;

  NotificationSettings? _settings;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  NotificationSettings? get settings => _settings;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String? get error => _error;
  bool get isMasterOff => _settings?.notificationsEnabled == false;

  /// Load current settings from server.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _settings = await _repository.get();
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Notification settings load failed: $e', stackTrace: st);
      _error = 'Failed to load settings.';
    }
    _loading = false;
    notifyListeners();
  }

  /// Update a single setting. Optimistic local update, then server persist.
  Future<bool> updateSetting({
    bool? notificationsEnabled,
    bool? testReminders,
    bool? liveTestInvitations,
    bool? testResults,
    bool? groupAnnouncements,
    bool? groupMessages,
    bool? routineReminders,
    bool? aiReports,
    bool? systemUpdates,
    bool? testInvitations,
    bool? badgeEnabled,
    bool? pushEnabled,
    bool? quietHoursEnabled,
    String? quietFrom,
    String? quietTo,
  }) async {
    if (_settings == null || _saving) return false;
    final previous = _settings!;
    _settings = _settings!.copyWith(
      notificationsEnabled: notificationsEnabled,
      testReminders: testReminders,
      liveTestInvitations: liveTestInvitations,
      testResults: testResults,
      groupAnnouncements: groupAnnouncements,
      groupMessages: groupMessages,
      routineReminders: routineReminders,
      aiReports: aiReports,
      systemUpdates: systemUpdates,
      testInvitations: testInvitations,
      badgeEnabled: badgeEnabled,
      pushEnabled: pushEnabled,
      quietHoursEnabled: quietHoursEnabled,
      quietFrom: quietFrom,
      quietTo: quietTo,
    );
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      _settings = await _repository.update(_settings!);
      _saving = false;
      notifyListeners();
      return true;
    } on AppError catch (e) {
      _settings = previous; // rollback
      _error = e.message;
      _saving = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.error('Notification settings save failed: $e', stackTrace: st);
      _settings = previous;
      _error = 'Failed to save settings.';
      _saving = false;
      notifyListeners();
      return false;
    }
  }
}
