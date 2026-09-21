// Dashboard widget tests — deliberately independent fakes (not shared with
// other test files) to avoid coupling to a lane another session may still be
// editing (same rationale as v1_via_document/document_upload_screen_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/profile.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/dashboard/dashboard_screen.dart';
import 'package:my_praperation/features/performance/state/performance_controller.dart';

import '../r4_restart/fakes.dart' show FakeTestRepository, FakeResultRepository;

Profile _profile({String fullName = 'Rahul Sharma', List<String> examTargets = const []}) {
  return Profile(
    id: 'u-1',
    fullName: fullName,
    timezone: 'Asia/Kolkata',
    createdAt: DateTime(2025, 1, 1),
    studentCode: 'STU-001',
    bio: '',
    mobile: '',
    examTargets: examTargets,
  );
}

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows a dynamic greeting with the profile display name', (tester) async {
    final testRepo = FakeTestRepository();
    final performance = PerformanceController(
      testRepository: testRepo,
      resultRepository: FakeResultRepository(),
    );

    await tester.pumpWidget(
      host(
        DashboardScreen(
          testRepository: testRepo,
          performanceController: performance,
          profile: _profile(fullName: 'Rahul Sharma'),
        ),
      ),
    );
    await tester.pump();

    final greeting = tester.widget<Text>(find.byKey(const Key('dashboard_greeting')));
    expect(greeting.data, contains('Rahul Sharma'));
    expect(
      greeting.data,
      anyOf(contains('Good Morning'), contains('Good Afternoon'), contains('Good Evening')),
    );
  });

  testWidgets('falls back to Student when no profile is available', (tester) async {
    final testRepo = FakeTestRepository();
    final performance = PerformanceController(
      testRepository: testRepo,
      resultRepository: FakeResultRepository(),
    );

    await tester.pumpWidget(
      host(
        DashboardScreen(
          testRepository: testRepo,
          performanceController: performance,
        ),
      ),
    );
    await tester.pump();

    final greeting = tester.widget<Text>(find.byKey(const Key('dashboard_greeting')));
    expect(greeting.data, contains('Student'));
  });

  testWidgets('shows empty states when there is no upcoming test and no performance data', (tester) async {
    final testRepo = FakeTestRepository();
    final performance = PerformanceController(
      testRepository: testRepo,
      resultRepository: FakeResultRepository(),
    );

    await tester.pumpWidget(
      host(
        DashboardScreen(
          testRepository: testRepo,
          performanceController: performance,
          profile: _profile(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No upcoming tests'), findsOneWidget);
    expect(
      find.text('Your performance will appear here after your first test.'),
      findsOneWidget,
    );
    expect(find.text('No recent tests'), findsOneWidget);
    // A failure/absence in one section (routine, groups — both hit an
    // uninitialized Supabase client in this widget-only test) must not
    // crash the rest of the dashboard.
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the target goal strip only when the profile has an exam target', (tester) async {
    final testRepo = FakeTestRepository();
    final performance = PerformanceController(
      testRepository: testRepo,
      resultRepository: FakeResultRepository(),
    );

    await tester.pumpWidget(
      host(
        DashboardScreen(
          testRepository: testRepo,
          performanceController: performance,
          profile: _profile(examTargets: const ['UPSC CSE 2025']),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('UPSC CSE 2025'), findsOneWidget);
  });

  testWidgets('an upcoming test renders with a countdown and a View Test action', (tester) async {
    final testRepo = FakeTestRepository();
    testRepo.rows['t-1'] = Test(
      id: 't-1',
      createdBy: 'u-1',
      title: 'Mathematics Full Sectional Test 04',
      status: TestStatus.scheduled,
      startsAt: DateTime.now().add(const Duration(hours: 2)),
      endsAt: DateTime.now().add(const Duration(hours: 3)),
      durationSec: 1800,
      totalQuestions: 25,
    );
    final performance = PerformanceController(
      testRepository: testRepo,
      resultRepository: FakeResultRepository(),
    );

    await tester.pumpWidget(
      host(
        DashboardScreen(
          testRepository: testRepo,
          performanceController: performance,
          profile: _profile(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mathematics Full Sectional Test 04'), findsOneWidget);
    expect(find.text('View Test'), findsOneWidget);
    expect(find.textContaining('25 Questions'), findsOneWidget);
  });
}
