import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group_rule.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';

/// Rules state for one group. Loaded by the rules section / screen.
/// Members see rules; authorized managers (MANAGE_MEMBERS) can CRUD.
class GroupRulesController extends DisposableNotifier {
  GroupRulesController({required this.groupId, GroupRepository? repository})
    : _repo = repository ?? const SupabaseGroupRepository();

  final String groupId;
  final GroupRepository _repo;

  List<GroupRule> _rules = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  final bool _busy = false;
  String? _error;

  // single-flight action tracking
  String? _actingId; // rule being edited/deleted
  bool _saving = false;

  List<GroupRule> get rules => _rules;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get isBusy => _busy;
  bool get isSaving => _saving;
  String? get error => _error;
  String? get actingId => _actingId;
  bool get hasRules => _rules.isNotEmpty;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _rules = await _repo.groupRules(groupId);
    } on AppError catch (e) {
      _rules = const [];
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group rules load failed: $e', stackTrace: st);
      _rules = const [];
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Creates a rule. Single-flight. Re-reads after success or failure.
  Future<bool> createRule(String content) async {
    if (_saving || _busy) return false;
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      _error = 'Rule text cannot be empty.';
      notifyListeners();
      return false;
    }
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.createRule(groupId: groupId, ruleText: trimmed);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Create rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Updates a rule's content. Single-flight per rule. Re-reads after.
  Future<bool> updateRule(GroupRule rule, String content) async {
    if (_saving || _actingId == rule.id || _busy) return false;
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      _error = 'Rule text cannot be empty.';
      notifyListeners();
      return false;
    }
    _actingId = rule.id;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.updateRule(ruleId: rule.id, ruleText: trimmed);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Update rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _actingId = null;
      _saving = false;
      notifyListeners();
    }
  }

  /// Deletes a rule. Single-flight per rule. Re-reads after.
  Future<bool> deleteRule(GroupRule rule) async {
    if (_saving || _actingId == rule.id || _busy) return false;
    _actingId = rule.id;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.deleteRule(rule.id);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Delete rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _actingId = null;
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> _loadRules() async {
    try {
      _rules = await _repo.groupRules(groupId);
    } catch (e) {
      AppLogger.warning('Rules re-read failed: $e');
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
