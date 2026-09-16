// R4.11a — Test-kind foundation.
// test_mode stays 'self' for the Self family; the kind lives in
// settings.test_kind. Challenge with Friends ('live') and Group ('group')
// are unchanged. Zero schema changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/core/models/test_kind.dart';
import 'package:my_praperation/core/services/test_service.dart';
import 'package:my_praperation/features/test/test_creation_screen.dart';
import 'package:my_praperation/features/test/widgets/step_basic_details.dart';

Map<String, dynamic> _row({Object? settings = const {}, Object? config}) {
  final json = <String, dynamic>{
    'id': 't-1',
    'created_by': 'u-1',
    'title': 'T',
    'status': 'draft',
    'test_mode': 'self',
    'config': config,
  };
  if (settings != const {}) json['settings'] = settings;
  return json;
}

void main() {
  group('TestKind', () {
    test('fromSettings: missing / null / invalid → self', () {
      expect(TestKind.fromSettings(null), TestKind.self);
      expect(TestKind.fromSettings({}), TestKind.self);
      expect(TestKind.fromSettings({'test_kind': null}), TestKind.self);
      expect(TestKind.fromSettings({'test_kind': 42}), TestKind.self);
      expect(TestKind.fromSettings({'test_kind': 'adaptive'}), TestKind.self);
    });

    test('fromSettings: every known value round-trips', () {
      for (final k in TestKind.values) {
        expect(TestKind.fromSettings({'test_kind': k.dbValue}), k);
        expect(TestKind.fromDbValue(k.dbValue.toUpperCase()), k);
      }
    });

    test('applyTo preserves unrelated keys and overrides test_kind', () {
      final original = {'test_kind': 'self', 'shuffle': true, 'x': 1};
      final out = TestKind.practice.applyTo(original);
      expect(out, {'test_kind': 'practice', 'shuffle': true, 'x': 1});
      expect(original['test_kind'], 'self'); // input not mutated
      expect(TestKind.quick.applyTo(null), {'test_kind': 'quick'});
    });

    test('labels are the canonical user-facing names', () {
      expect(TestKind.self.label, 'Self');
      expect(TestKind.practice.label, 'Practice Test');
      expect(TestKind.quick.label, 'Quick Test');
      expect(TestKind.sectional.label, 'Sectional Test');
      expect(testTypeLabel(testMode: 'live', kind: TestKind.self),
          'Challenge with Friends');
      expect(testTypeLabel(testMode: 'group', kind: TestKind.self),
          'Group Test');
      // Kind never leaks into non-self modes.
      expect(testTypeLabel(testMode: 'live', kind: TestKind.practice),
          'Challenge with Friends');
      expect(testTypeLabel(testMode: null, kind: TestKind.quick), 'Quick Test');
      for (final k in TestKind.values) {
        expect(k.label, isNot(contains('Live')));
      }
    });
  });

  group('Test model config/settings', () {
    test('missing settings key → self, settings null', () {
      final t = Test.fromJson(_row());
      expect(t.settings, isNull);
      expect(t.testKind, TestKind.self);
      expect(t.typeLabel, 'Self');
    });

    test('null settings → self', () {
      final t = Test.fromJson(_row(settings: null));
      expect(t.settings, isNull);
      expect(t.testKind, TestKind.self);
    });

    test('non-map settings (bad data) → treated as absent', () {
      expect(Test.fromJson(_row(settings: 'oops')).settings, isNull);
      expect(Test.fromJson(_row(settings: ['a'])).testKind, TestKind.self);
    });

    for (final kind in TestKind.values) {
      test('settings.test_kind=${kind.dbValue} → ${kind.name}', () {
        final t = Test.fromJson(_row(settings: {'test_kind': kind.dbValue}));
        expect(t.testKind, kind);
        expect(t.testMode, 'self');
        expect(t.typeLabel, kind.label);
      });
    }

    test('unknown test_kind → self', () {
      final t = Test.fromJson(_row(settings: {'test_kind': 'marketplace'}));
      expect(t.testKind, TestKind.self);
    });

    test('live / group ignore test_kind and keep their labels', () {
      final live = Test.fromJson(
          {..._row(settings: {'test_kind': 'quick'}), 'test_mode': 'live'});
      expect(live.typeLabel, 'Challenge with Friends');
      final group = Test.fromJson(
          {..._row(settings: {'test_kind': 'quick'}), 'test_mode': 'group'});
      expect(group.typeLabel, 'Group Test');
    });

    test('round-trip preserves every config/settings key', () {
      final t = Test.fromJson(_row(
        settings: {'test_kind': 'sectional', 'custom': 'keep', 'n': 3},
        config: {'theme': 'dark', 'nested': {'a': 1}},
      ));
      final json = t.toJson();
      expect(json['settings'],
          {'test_kind': 'sectional', 'custom': 'keep', 'n': 3});
      expect(json['config'], {'theme': 'dark', 'nested': {'a': 1}});
      expect(json.containsKey('correct_option'), isFalse);
    });

    test('existing rows without settings still parse identically', () {
      final t = Test.fromJson({
        'id': 'x',
        'created_by': 'u',
        'title': 'legacy',
        'status': 'published',
        'test_mode': 'self',
        'duration_sec': 600,
      });
      expect(t.durationSec, 600);
      expect(t.config, isNull);
      expect(t.settings, isNull);
      expect(t.testKind, TestKind.self);
    });
  });

  group('Create/update payload', () {
    Map<String, dynamic> create(String mode, Map<String, dynamic>? settings) =>
        TestService.buildCreateTestParams(
          title: 'T',
          testMode: mode,
          settings: settings,
        );

    test('Practice / Quick / Sectional create as test_mode=self with kind',
        () {
      for (final k in [TestKind.practice, TestKind.quick, TestKind.sectional]) {
        final p = create('self', k.applyTo(null));
        expect(p['p_test_mode'], 'self');
        expect(p['p_settings'], {'test_kind': k.dbValue});
      }
    });

    test('Self keeps test_mode=self and explicit self kind', () {
      final p = create('self', TestKind.self.applyTo(null));
      expect(p['p_test_mode'], 'self');
      expect(p['p_settings'], {'test_kind': 'self'});
    });

    test('Challenge with Friends / Group payloads carry no test_kind', () {
      for (final mode in ['live', 'group']) {
        final p = create(mode, null);
        expect(p['p_test_mode'], mode);
        expect(p.containsKey('p_settings'), isFalse);
      }
    });

    test('update preserves unrelated settings keys', () {
      final existing = {'test_kind': 'self', 'keep_me': true};
      final p = TestService.buildUpdateTestParams(
        testId: 't-1',
        settings: TestKind.quick.applyTo(existing),
      );
      expect(p['p_settings'], {'test_kind': 'quick', 'keep_me': true});
    });
  });

  group('Creation defaults', () {
    test('kind defaults are sane and within the documented 60–21600 s range',
        () {
      expect(TestCreationScreen.quickDefaultDurationSec, 600);
      expect(TestCreationScreen.practiceDefaultDurationSec, 3 * 3600);
      expect(TestCreationScreen.practiceDefaultDurationSec, lessThanOrEqualTo(21600));
    });
  });

  group('StepBasicDetails test-type picker', () {
    Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

    test('TestTypeOption.resolve maps stored values to picker entries', () {
      expect(TestTypeOption.resolve('self', TestKind.practice)!.label,
          'Practice Test');
      expect(TestTypeOption.resolve('live', TestKind.practice)!.label,
          'Challenge with Friends');
      expect(TestTypeOption.resolve('group', TestKind.self)!.label,
          'Group Test');
      expect(TestTypeOption.resolve(null, TestKind.self), isNull);
      expect(TestTypeOption.resolve('bogus', TestKind.self), isNull);
    });

    testWidgets('shows all six labels and never "Live Test"', (tester) async {
      await tester.pumpWidget(wrap(StepBasicDetails(
        title: '',
        description: '',
        testMode: 'self',
        onTitleChanged: (_) {},
        onDescriptionChanged: (_) {},
        onTestModeChanged: (_) {},
        titleError: null,
      )));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      for (final label in [
        'Self',
        'Practice Test',
        'Quick Test',
        'Sectional Test',
        'Challenge with Friends',
        'Group Test',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Live Test'), findsNothing);
    });

    testWidgets('choosing Practice Test reports mode=self, kind=practice',
        (tester) async {
      String? mode;
      TestKind? kind;
      await tester.pumpWidget(wrap(StepBasicDetails(
        title: '',
        description: '',
        testMode: 'self',
        onTitleChanged: (_) {},
        onDescriptionChanged: (_) {},
        onTestModeChanged: (m) => mode = m,
        onTestKindChanged: (k) => kind = k,
        titleError: null,
      )));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practice Test').last);
      await tester.pumpAndSettle();

      expect(mode, 'self');
      expect(kind, TestKind.practice);
    });

    testWidgets('choosing Challenge with Friends reports mode=live, kind=self',
        (tester) async {
      String? mode;
      TestKind? kind;
      await tester.pumpWidget(wrap(StepBasicDetails(
        title: '',
        description: '',
        testMode: 'self',
        testKind: TestKind.quick,
        onTitleChanged: (_) {},
        onDescriptionChanged: (_) {},
        onTestModeChanged: (m) => mode = m,
        onTestKindChanged: (k) => kind = k,
        titleError: null,
      )));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Challenge with Friends').last);
      await tester.pumpAndSettle();

      expect(mode, 'live');
      expect(kind, TestKind.self);
    });
  });
}
