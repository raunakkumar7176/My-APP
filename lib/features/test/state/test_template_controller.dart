import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test_template.dart';
import '../data/test_template_repository.dart';
import 'disposable_notifier.dart';

/// G19 — Loads and manages the user's test templates.
/// Screens render its state and call its methods.
class TestTemplateController extends DisposableNotifier {
  TestTemplateController({TestTemplateRepository? repository})
      : _repo = repository ?? const SupabaseTestTemplateRepository();

  final TestTemplateRepository _repo;

  List<TestTemplate> _myTemplates = [];
  List<TestTemplate> _groupTemplates = [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  String? _groupError;

  List<TestTemplate> get myTemplates => _myTemplates;
  List<TestTemplate> get groupTemplates => _groupTemplates;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get error => _error;
  String? get groupError => _groupError;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _groupError = null;
    notifyListeners();

    try {
      _myTemplates = await _repo.listMy();
    } on AppError catch (e) {
      _error = e.message;
      _myTemplates = const [];
    } catch (e, st) {
      AppLogger.error('Template load failed: $e', stackTrace: st);
      _error = 'Failed to load templates. Please try again.';
      _myTemplates = const [];
    }

    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> loadGroupTemplates(String groupId) async {
    try {
      _groupTemplates = await _repo.listForGroup(groupId);
      _groupError = null;
    } on AppError catch (e) {
      _groupError = e.message;
      _groupTemplates = const [];
    } catch (e, st) {
      AppLogger.error('Group template load failed: $e', stackTrace: st);
      _groupError = 'Failed to load group templates.';
      _groupTemplates = const [];
    }
    notifyListeners();
  }

  Future<void> refresh() => load();

  Future<void> delete(String id) async {
    await _repo.delete(id);
    _myTemplates.removeWhere((t) => t.id == id);
    _groupTemplates.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  Future<void> loadAfterMutation() async {
    await load();
  }
}
