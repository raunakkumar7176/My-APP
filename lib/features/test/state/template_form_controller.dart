import '../../../core/errors/app_error.dart';
import '../../../core/models/test_template.dart';
import '../data/test_template_repository.dart';
import 'disposable_notifier.dart';

/// G19 — Owns the create/edit flow for a single test template.
/// Screens render its state and call its methods.
class TemplateFormController extends DisposableNotifier {
  TemplateFormController({
    this.editingTemplateId,
    TestTemplateRepository? repository,
  }) : _repo = repository ?? const SupabaseTestTemplateRepository();

  final String? editingTemplateId;
  final TestTemplateRepository _repo;

  String title = '';
  String description = '';
  String? groupId;
  Map<String, dynamic> configuration = {};

  TestTemplate? _persisted;
  bool _loading = false;
  bool _busy = false;
  String? _loadError;

  TestTemplate? get persistedTemplate => _persisted;
  bool get isPersisted => _persisted != null;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  String? get loadError => _loadError;
  bool get canSave => title.trim().isNotEmpty;

  Future<void> loadForEdit() async {
    final id = editingTemplateId;
    if (id == null) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final template = await _repo.getById(id);
      if (template == null) {
        _loadError = 'Template not found.';
      } else {
        _persisted = template;
        title = template.title;
        description = template.description;
        groupId = template.groupId;
        configuration = Map<String, dynamic>.from(template.configuration);
      }
    } on AppError catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setTitle(String v) => _set(() => title = v);
  void setDescription(String v) => _set(() => description = v);
  void setConfiguration(Map<String, dynamic> v) =>
      _set(() => configuration = v);

  void presetFromConfiguration({
    required String templateTitle,
    String templateDescription = '',
    String? templateGroupId,
    required Map<String, dynamic> templateConfiguration,
  }) => _set(() {
    title = templateTitle;
    description = templateDescription;
    groupId = templateGroupId;
    configuration = Map<String, dynamic>.from(templateConfiguration);
  });

  Future<String> save() async {
    if (_busy) throw const ValidationError(message: 'Please wait…');
    if (title.trim().isEmpty) {
      throw const ValidationError(message: 'Title is required');
    }
    _busy = true;
    notifyListeners();
    try {
      final input = TestTemplateInput(
        title: title.trim(),
        description: description.trim(),
        groupId: groupId,
        configuration: configuration,
      );
      final existing = _persisted;
      if (existing != null) {
        await _repo.update(existing.id, input);
        return existing.id;
      } else {
        final created = await _repo.create(input);
        _persisted = created;
        notifyListeners();
        return created.id;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _set(void Function() body) {
    body();
    notifyListeners();
  }
}
