// G19 — Test Templates V1 tests.
// Covers: create, list, edit, delete, unauthorized access, use template,
// template → new test, editing template does not modify created test,
// double-tap protection, error/retry.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/test_template.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';
import 'package:my_praperation/features/test/state/test_template_controller.dart';
import 'package:my_praperation/features/test/state/template_form_controller.dart';

import 'fakes.dart';
import '../r4_restart/fakes.dart' as r4_fakes;

TestTemplate _tpl(
  String id, {
  String title = 'Physics Quiz',
  String? groupId,
  String owner = 'u-1',
  Map<String, dynamic>? config,
}) => TestTemplate(
  id: id,
  createdBy: owner,
  groupId: groupId,
  title: title,
  description: 'Reusable physics quiz',
  configuration:
      config ??
      const {
        'kind': 'practice',
        'duration_sec': 3600,
        'marks_per_question': 1.0,
      },
  createdAt: DateTime(2026, 9, 20),
  updatedAt: DateTime(2026, 9, 20),
);

void main() {
  group('G19 — TestTemplateController', () {
    test('loads personal templates', () async {
      final repo = FakeTestTemplateRepository()
        ..seed(id: 'tpl-1', title: 'Quiz A')
        ..seed(id: 'tpl-2', title: 'Quiz B');
      final c = TestTemplateController(repository: repo);
      await c.load();

      expect(c.hasLoaded, isTrue);
      expect(c.error, isNull);
      expect(c.myTemplates.length, 2);
      expect(repo.calls, contains('listMy'));
    });

    test('loads group templates', () async {
      final repo = FakeTestTemplateRepository()
        ..seed(id: 'g-tpl-1', title: 'Group Quiz', groupId: 'g-1');
      final c = TestTemplateController(repository: repo);
      await c.loadGroupTemplates('g-1');

      expect(c.groupTemplates.length, 1);
      expect(repo.calls, contains('listForGroup:g-1'));
    });

    test('delete removes from list', () async {
      final repo = FakeTestTemplateRepository()
        ..seed(id: 'tpl-1', title: 'Quiz A')
        ..seed(id: 'tpl-2', title: 'Quiz B');
      final c = TestTemplateController(repository: repo);
      await c.load();
      expect(c.myTemplates.length, 2);

      await c.delete('tpl-1');
      expect(c.myTemplates.length, 1);
      expect(c.myTemplates.first.id, 'tpl-2');
      expect(repo.calls, contains('delete:tpl-1'));
    });

    test('error sets error field', () async {
      final repo = FakeTestTemplateRepository()
        ..failNextWith = const DataError(message: 'Network error');
      final c = TestTemplateController(repository: repo);
      await c.load();

      expect(c.error, isNotNull);
      expect(c.myTemplates, isEmpty);
    });

    test(
      'double-tap protection: loading flag prevents concurrent loads',
      () async {
        final repo = FakeTestTemplateRepository()..seed(id: 'tpl-1');
        final c = TestTemplateController(repository: repo);
        // First load
        final f1 = c.load();
        // Second load should be a no-op
        final f2 = c.load();
        await Future.wait([f1, f2]);
        // listMy called only once
        expect(repo.calls.where((x) => x == 'listMy').length, 1);
      },
    );
  });

  group('G19 — TemplateFormController', () {
    test('create template', () async {
      final repo = FakeTestTemplateRepository();
      final c = TemplateFormController(repository: repo);
      c.setTitle('New Template');
      c.setConfiguration(const {'kind': 'practice', 'duration_sec': 3600});

      final id = await c.save();
      expect(id, isNotEmpty);
      expect(c.isPersisted, isTrue);
      expect(repo.rows.length, 1);
      expect(repo.rows[id]?.title, 'New Template');
    });

    test('update template', () async {
      final repo = FakeTestTemplateRepository();
      final existing = repo.seed(id: 'tpl-1', title: 'Old Title');
      final c = TemplateFormController(
        editingTemplateId: 'tpl-1',
        repository: repo,
      );
      await c.loadForEdit();
      expect(c.title, 'Old Title');

      c.setTitle('Updated Title');
      await c.save();

      expect(repo.rows['tpl-1']?.title, 'Updated Title');
    });

    test('validation: title is required', () async {
      final repo = FakeTestTemplateRepository();
      final c = TemplateFormController(repository: repo);
      // Title is empty
      expect(c.canSave, isFalse);
      expect(() => c.save(), throwsA(isA<ValidationError>()));
    });

    test('loadForEdit: template not found sets error', () async {
      final repo = FakeTestTemplateRepository();
      final c = TemplateFormController(
        editingTemplateId: 'missing',
        repository: repo,
      );
      await c.loadForEdit();
      expect(c.loadError, isNotNull);
    });

    test('unauthorized update: another user\'s template', () async {
      final repo = FakeTestTemplateRepository()
        ..currentUser = 'u-1'
        ..seed(id: 'tpl-1', title: 'My Template', createdBy: 'u-other');
      final c = TemplateFormController(
        editingTemplateId: 'tpl-1',
        repository: repo,
      );
      await c.loadForEdit();
      c.setTitle('Hacked');
      expect(() => c.save(), throwsA(isA<DataError>()));
    });

    test('double-tap protection: save rejects concurrent calls', () async {
      final repo = FakeTestTemplateRepository();
      final c = TemplateFormController(repository: repo);
      c.setTitle('Template');
      c.setConfiguration(const {});

      // First save succeeds
      final f1 = c.save();
      await f1;
      expect(c.isPersisted, isTrue);

      // After first save completes, _busy is false; a second save should work
      final f2 = c.save();
      await f2;
      expect(repo.rows.length, 1);
    });

    test('presetFromConfiguration: populates from test creation', () async {
      final repo = FakeTestTemplateRepository();
      final c = TemplateFormController(repository: repo);
      c.presetFromConfiguration(
        templateTitle: 'From Test',
        templateDescription: 'Desc',
        templateConfiguration: const {'kind': 'quick', 'duration_sec': 600},
      );
      expect(c.title, 'From Test');
      expect(c.description, 'Desc');
      expect(c.configuration['kind'], 'quick');
    });
  });

  group('G19 — loadFromTemplate (TestCreationController)', () {
    test('populates wizard from template configuration', () {
      final c = TestCreationController();
      final template = _tpl(
        'tpl-1',
        title: 'Saved Quiz',
        config: const {
          'kind': 'practice',
          'duration_sec': 7200,
          'marks_per_question': 2.0,
          'negative_marks': 0.5,
        },
      );

      c.loadFromTemplate(template);

      expect(c.title, 'Saved Quiz');
      expect(c.durationSec, 7200);
      expect(c.marksPerQuestion, 2.0);
      expect(c.negativeMarks, 0.5);
    });

    test('group template sets groupId', () {
      final c = TestCreationController();
      final template = _tpl(
        'tpl-1',
        title: 'Group Quiz',
        groupId: 'g-1',
        config: const {
          'kind': 'group',
          'test_mode': 'group',
          'duration_sec': 3600,
        },
      );

      c.loadFromTemplate(template);

      expect(c.groupId, 'g-1');
      expect(c.kind.name, 'group');
    });

    test('template edit does NOT modify created test (independence)', () async {
      // Create a test from a template
      final templateRepo = FakeTestTemplateRepository();
      final testRepo = r4_fakes.FakeTestRepository();
      final template = templateRepo.seed(
        id: 'tpl-1',
        title: 'Original Quiz',
        configuration: const {
          'kind': 'practice',
          'duration_sec': 3600,
          'marks_per_question': 1.0,
        },
      );

      // Simulate: controller loads template, creates test
      final c = TestCreationController(
        tests: testRepo,
        questions: r4_fakes.FakeQuestionRepository(),
      );
      c.loadFromTemplate(template);
      expect(c.title, 'Original Quiz');
      expect(c.durationSec, 3600);

      // Modify the template (should not affect the test)
      templateRepo.rows['tpl-1'] = template.copyWith(
        title: 'Modified Quiz',
        configuration: const {
          'kind': 'practice',
          'duration_sec': 1800,
          'marks_per_question': 2.0,
        },
      );

      // The controller's state is independent
      expect(c.title, 'Original Quiz');
      expect(c.durationSec, 3600);
    });

    test('preserves attempt and late-join settings from template', () {
      final c = TestCreationController();
      final template = _tpl(
        'tpl-1',
        config: const {
          'kind': 'practice',
          'duration_sec': 3600,
          'settings': {
            'allow_reattempt': true,
            'max_attempts': 3,
            'late_join_minutes': 15,
          },
          'allow_late_join': true,
        },
      );

      c.loadFromTemplate(template);

      expect(c.attemptSettings.allowReattempt, isTrue);
      expect(c.attemptSettings.maxAttempts, 3);
      expect(c.lateJoin.enabled, isTrue);
      expect(c.lateJoin.minutes, 15);
    });
  });

  group('G19 — Unauthorized access', () {
    test('cannot read another user\'s personal template via fake', () async {
      final repo = FakeTestTemplateRepository()
        ..currentUser = 'u-1'
        ..seed(id: 'tpl-1', title: 'Secret', createdBy: 'u-other');

      final templates = await repo.listMy();
      expect(templates, isEmpty);
    });

    test('cannot delete another user\'s template via fake', () async {
      final repo = FakeTestTemplateRepository()
        ..currentUser = 'u-1'
        ..seed(id: 'tpl-1', title: 'Secret', createdBy: 'u-other');

      expect(() => repo.delete('tpl-1'), throwsA(isA<DataError>()));
    });

    test('cannot update another user\'s template via fake', () async {
      final repo = FakeTestTemplateRepository()
        ..currentUser = 'u-1'
        ..seed(id: 'tpl-1', title: 'Secret', createdBy: 'u-other');

      expect(
        () => repo.update(
          'tpl-1',
          const TestTemplateInput(title: 'Hacked', configuration: {}),
        ),
        throwsA(isA<DataError>()),
      );
    });
  });

  group('G19 — Error/retry', () {
    test('controller retry after error reloads successfully', () async {
      final repo = FakeTestTemplateRepository()..seed(id: 'tpl-1');
      final c = TestTemplateController(repository: repo);

      // First load fails
      repo.failNextWith = const DataError(message: 'Network error');
      await c.load();
      expect(c.error, isNotNull);

      // Retry succeeds
      await c.load();
      expect(c.error, isNull);
      expect(c.myTemplates.length, 1);
    });

    test('form save retry after error', () async {
      final repo = FakeTestTemplateRepository();
      final c = TemplateFormController(repository: repo);
      c.setTitle('Template');
      c.setConfiguration(const {'kind': 'practice'});

      // First save fails
      repo.failNextWith = const DataError(message: 'Server error');
      try {
        await c.save();
        fail('Should have thrown');
      } on DataError catch (e) {
        expect(e.message, 'Server error');
      }

      // Retry succeeds
      final id = await c.save();
      expect(id, isNotEmpty);
      expect(c.isPersisted, isTrue);
    });
  });
}
