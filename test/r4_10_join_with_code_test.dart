// Challenge with Friends — join by code (client side).
// Backend-dependent parts (rpc_start_attempt_by_code shape, coded-test row
// readability, p_access_code handling) are not exercised here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/widgets/join_with_code_sheet.dart';

void main() {
  group('JoinWithCodeSheet.fallbackTest', () {
    test('carries the test id and the server-provided title', () {
      final t = JoinWithCodeSheet.fallbackTest(testId: 't-1', title: ' Maths ');
      expect(t.id, 't-1');
      expect(t.title, 'Maths');
      expect(t.testMode, 'live');
      expect(t.status, TestStatus.live);
      expect(t.shuffleQuestions, isFalse);
    });

    test('uses the canonical user-facing name when no title is available',
        () {
      expect(JoinWithCodeSheet.fallbackTest(testId: 't-1').title,
          'Challenge with Friends');
      expect(JoinWithCodeSheet.fallbackTest(testId: 't-1', title: '  ').title,
          'Challenge with Friends');
      expect(JoinWithCodeSheet.fallbackTest(testId: 't-1').title,
          isNot(contains('Live')));
    });
  });

  group('JoinWithCodeSheet widget', () {
    testWidgets('renders and rejects an empty code without any network call',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: JoinWithCodeSheet()),
      ));

      expect(find.text('Join with code'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      // Validation error shown inline; no Supabase client was touched
      // (SupabaseService.client would throw StateError in tests).
      expect(find.text('Enter a test code.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
    });
  });
}
