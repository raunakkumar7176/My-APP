import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/features/tests/presentation/screens/candidate_join_screen.dart';
import 'package:my_praperation/features/tests/presentation/screens/candidate_waiting_room_screen.dart';
import 'package:my_praperation/features/tests/services/peer_challenge_service.dart';

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(theme: ThemeData.light(), home: child);
}

Widget _buildRouterApp({
  required Widget child,
  String initialLocation = '/tests/join',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/tests/join', builder: (context, state) => child),
      GoRoute(
        path: '/tests/challenge/:pin/waiting-room',
        builder: (context, state) => Scaffold(
          body: Text('Waiting Room: ${state.pathParameters['pin']}'),
        ),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router, theme: ThemeData.light());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PeerChallengeService', () {
    test('PIN generation produces valid 6-digit numeric string', () async {
      final session = await PeerChallengeService.instance.createSession(
        testId: 'test_upsc_prelims_01',
        durationMinutes: 30,
      );

      expect(session.pinCode, isNotEmpty);
      expect(session.pinCode.length, equals(6));
      expect(RegExp(r'^\d{6}$').hasMatch(session.pinCode), isTrue);
      expect(session.isHost, isTrue);
      expect(session.status, equals('waiting_room'));
      expect(session.durationMinutes, equals(30));
    });

    test('Server-sync clock offset and remaining time calculation', () {
      final service = PeerChallengeService.instance;

      // 1. Set explicit clock offset (e.g. +10 seconds ahead of client UTC)
      service.setClockOffsetForTesting(const Duration(seconds: 10));
      expect(service.isClockCalibrated, isTrue);

      final clientUtc = DateTime.now().toUtc();
      final diff = service.serverNow.difference(clientUtc);
      expect(diff.inSeconds, inInclusiveRange(9, 11));

      // 2. Countdown remaining for future commencement
      final futureCommenceAt = service.serverNow.add(
        const Duration(seconds: 5),
      );
      final countdownSec = service.calculateCommenceCountdown(futureCommenceAt);
      expect(countdownSec, inInclusiveRange(4, 5));

      // 3. Countdown remaining for already-commenced exam
      final pastCommenceAt = service.serverNow.subtract(
        const Duration(seconds: 1),
      );
      final zeroCountdown = service.calculateCommenceCountdown(pastCommenceAt);
      expect(zeroCountdown, equals(0));

      // 4. Remaining exam duration calculation
      final examCommence = service.serverNow.subtract(
        const Duration(minutes: 10),
      );
      final remaining = service.calculateRemainingExamDuration(
        commenceAt: examCommence,
        durationMinutes: 30,
      );
      expect(remaining.inMinutes, inInclusiveRange(19, 20));

      // 5. Expired exam duration returns Duration.zero
      final concludedCommence = service.serverNow.subtract(
        const Duration(minutes: 60),
      );
      final expired = service.calculateRemainingExamDuration(
        commenceAt: concludedCommence,
        durationMinutes: 30,
      );
      expect(expired, equals(Duration.zero));
    });
  });

  group('CandidateJoinScreen', () {
    testWidgets(
      'Input format validation: rejects non-6-digit PIN and accepts valid PIN',
      (tester) async {
        await tester.pumpWidget(
          _buildRouterApp(child: const CandidateJoinScreen()),
        );
        await tester.pump();

        // Enter 4 digits (insufficient length)
        final pinInput = find.byKey(const Key('challenge_pin_input'));
        expect(pinInput, findsOneWidget);

        await tester.enterText(pinInput, '1234');
        await tester.pump();

        final enterBtn = find.byKey(const Key('enter_waiting_room_btn'));
        expect(enterBtn, findsOneWidget);

        await tester.tap(enterBtn);
        await tester.pump();

        // Verify validation error
        expect(find.text('PIN must be exactly 6 digits'), findsOneWidget);

        // Enter valid 6-digit PIN
        await tester.enterText(pinInput, '654321');
        await tester.pump();

        // Tap button and verify error clears
        await tester.tap(enterBtn);
        await tester.pump();

        expect(find.text('PIN must be exactly 6 digits'), findsNothing);
      },
    );

    testWidgets('Renders error banner on invalid or concluded PIN', (
      tester,
    ) async {
      // Register an already-concluded mock session
      const concludedSession = ChallengeSession(
        sessionId: 'sess_concluded_888999',
        testId: 'test_history_01',
        hostId: 'host_invigilator_1',
        pinCode: '888999',
        status: 'concluded',
        durationMinutes: 30,
      );
      PeerChallengeService.instance.registerMockSession(concludedSession);

      await tester.pumpWidget(
        _buildRouterApp(child: const CandidateJoinScreen()),
      );
      await tester.pump();

      final pinInput = find.byKey(const Key('challenge_pin_input'));
      await tester.enterText(pinInput, '888999');
      await tester.pump();

      final enterBtn = find.byKey(const Key('enter_waiting_room_btn'));
      await tester.tap(enterBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify academic error banner rendering
      expect(
        find.text('This examination session has already concluded.'),
        findsOneWidget,
      );
    });
  });

  group('CandidateWaitingRoomScreen', () {
    testWidgets('Renders Candidate Roll Call header and session details', (
      tester,
    ) async {
      const session = ChallengeSession(
        sessionId: 'sess_rollcall_test',
        testId: 'test_upsc_polity_2026',
        hostId: 'host_invigilator_99',
        pinCode: '918273',
        status: 'waiting_room',
        durationMinutes: 45,
        isHost: false,
        testTitle: 'Polity & Constitution Grand Mock',
        subject: 'General Studies Paper II',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CandidateWaitingRoomScreen(session: session),
        ),
      );
      await tester.pump();

      // Verify PIN and Title details
      expect(find.text('918 273'), findsOneWidget);
      expect(find.text('Polity & Constitution Grand Mock'), findsOneWidget);
      expect(find.text('GENERAL STUDIES PAPER II'), findsOneWidget);

      // Verify Roll Call section header
      expect(find.text('Candidate Roll Call'), findsOneWidget);
    });

    testWidgets('Host view displays "Commence Examination" action', (
      tester,
    ) async {
      const hostSession = ChallengeSession(
        sessionId: 'sess_host_view',
        testId: 'test_polity',
        hostId: 'invigilator_lead',
        pinCode: '556677',
        status: 'waiting_room',
        durationMinutes: 60,
        isHost: true,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CandidateWaitingRoomScreen(session: hostSession),
        ),
      );
      await tester.pump();

      // Host view MUST display commencement button
      expect(
        find.text('Commence Examination for All Candidates ➔'),
        findsOneWidget,
      );
      // Candidate awaiting message MUST NOT be present
      expect(find.text('Awaiting invigilator start signal...'), findsNothing);
    });

    testWidgets('Candidate view displays "Awaiting Invigilator" status', (
      tester,
    ) async {
      const candidateSession = ChallengeSession(
        sessionId: 'sess_cand_view',
        testId: 'test_polity',
        hostId: 'invigilator_other',
        pinCode: '112233',
        status: 'waiting_room',
        durationMinutes: 60,
        isHost: false,
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CandidateWaitingRoomScreen(session: candidateSession),
        ),
      );
      await tester.pump();

      // Candidate view MUST display synchronized waiting indicator
      expect(find.text('Awaiting invigilator start signal...'), findsOneWidget);
      expect(find.text('Synchronized with examination server'), findsOneWidget);
      // Host commencement button MUST NOT be present
      expect(
        find.text('Commence Examination for All Candidates ➔'),
        findsNothing,
      );
    });
  });
}
