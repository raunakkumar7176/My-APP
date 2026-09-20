// In-memory TestTemplateRepository for G19 tests. No Supabase.

import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/test_template.dart';
import 'package:my_praperation/features/test/data/test_template_repository.dart';

class FakeTestTemplateRepository implements TestTemplateRepository {
  final Map<String, TestTemplate> rows = {};
  final List<String> calls = [];
  int nextId = 1;
  String currentUser = 'u-1';

  /// When set, the next mutating call throws this.
  Object? failNextWith;

  void _maybeFail() {
    final f = failNextWith;
    if (f != null) {
      failNextWith = null;
      throw f;
    }
  }

  TestTemplate seed({
    String? id,
    String title = 'Physics Template',
    String description = 'A reusable physics quiz config',
    String? groupId,
    String? createdBy,
    Map<String, dynamic>? configuration,
  }) {
    final templateId = id ?? 'tpl-${nextId++}';
    final template = TestTemplate(
      id: templateId,
      createdBy: createdBy ?? currentUser,
      groupId: groupId,
      title: title,
      description: description,
      configuration: configuration ??
          const {
            'kind': 'practice',
            'duration_sec': 3600,
            'marks_per_question': 1.0,
          },
      createdAt: DateTime(2026, 9, 20),
      updatedAt: DateTime(2026, 9, 20),
    );
    rows[templateId] = template;
    return template;
  }

  @override
  Future<List<TestTemplate>> listMy({int limit = 50}) async {
    calls.add('listMy');
    _maybeFail();
    return rows.values
        .where((t) => t.createdBy == currentUser && t.groupId == null)
        .toList()
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  }

  @override
  Future<List<TestTemplate>> listForGroup(
    String groupId, {
    int limit = 50,
  }) async {
    calls.add('listForGroup:$groupId');
    _maybeFail();
    return rows.values.where((t) => t.groupId == groupId).toList()
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  }

  @override
  Future<TestTemplate?> getById(String id) async {
    calls.add('getById:$id');
    _maybeFail();
    return rows[id];
  }

  @override
  Future<TestTemplate> create(TestTemplateInput input) async {
    calls.add('create');
    _maybeFail();
    final id = 'tpl-${nextId++}';
    final template = TestTemplate(
      id: id,
      createdBy: currentUser,
      groupId: input.groupId,
      title: input.title,
      description: input.description,
      configuration: input.configuration,
      createdAt: DateTime(2026, 9, 20),
      updatedAt: DateTime(2026, 9, 20),
    );
    rows[id] = template;
    return template;
  }

  @override
  Future<void> update(String id, TestTemplateInput input) async {
    calls.add('update:$id');
    _maybeFail();
    final existing = rows[id];
    if (existing == null) {
      throw const DataError(message: 'Template not found.');
    }
    if (existing.createdBy != currentUser) {
      throw const DataError(
        message: 'You do not have permission to perform this action.',
      );
    }
    rows[id] = existing.copyWith(
      title: input.title,
      description: input.description,
      configuration: input.configuration,
    );
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    _maybeFail();
    final existing = rows[id];
    if (existing == null) {
      throw const DataError(message: 'Template not found.');
    }
    if (existing.createdBy != currentUser) {
      throw const DataError(
        message: 'You do not have permission to perform this action.',
      );
    }
    rows.remove(id);
  }
}
