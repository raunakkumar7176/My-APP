import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/models/profile.dart';
import '../core/services/auth_service.dart';
import '../core/services/profile_service.dart';
import '../features/calendar/screens/calendar_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/group/screens/group_create_screen.dart';
import '../features/group/screens/group_discussion_screen.dart';
import '../features/group/screens/group_hub_screen.dart';
import '../features/group/state/group_hub_controller.dart';
import '../features/group/screens/group_leaderboard_screen.dart';
import '../features/group/screens/group_list_screen.dart';
import '../features/group/screens/group_members_screen.dart';
import '../features/group/screens/group_notifications_screen.dart';
import '../features/group/screens/group_settings_screen.dart';
import '../features/group/screens/group_test_results_screen.dart';
import '../features/group/screens/group_tests_screen.dart';
import '../features/leaderboard/leaderboard_hub_screen.dart';
import '../features/notifications/notifications_hub_screen.dart';
import '../features/notifications/screens/notification_settings_screen.dart';
import '../features/performance/performance_screen.dart';
import '../features/profile/connections_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/refer_and_earn_screen.dart';
import '../features/profile/screens/avatar_viewer_screen.dart';
import '../features/community/screens/community_hub_screen.dart';
import '../features/about/screens/about_app_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_shell.dart';
import '../features/study/material_detail_screen.dart';
import '../features/study/material_list_screen.dart';
import '../features/study/study.dart';
import '../features/study/syllabus_detail_screen.dart';
import '../features/routine/screens/routine_list_screen.dart';
import '../features/routine/screens/routine_create_screen.dart';
import '../features/routine/screens/routine_detail_screen.dart';
import '../features/routine/screens/routine_history_screen.dart';
import '../features/test/screens/challenge_join_screen.dart';
import '../features/test/screens/challenge_merit_list_screen.dart';
import '../features/test/screens/challenge_waiting_room_screen.dart';
import '../features/test/state/challenge_controller.dart';
import '../features/test/screens/question_bank_screen.dart';
import '../features/test/screens/question_bank_detail_screen.dart';
import '../features/test/screens/question_review_screen.dart';
import '../features/test/screens/test_creation_screen.dart';
import '../features/test/screens/camera_capture_screen.dart';
import '../features/test/screens/document_upload_screen.dart';
import '../features/test/screens/my_uploads_screen.dart';
import '../features/test/screens/ai_generation_screen.dart';
import '../features/test/screens/template_listing_screen.dart';
import '../features/test/screens/template_form_screen.dart';
import '../features/test/widgets/question_source_step.dart';
import '../features/test/screens/test_detail_screen.dart';
import '../features/test/screens/test_listing_screen.dart';
import '../features/test/screens/test_result_screen.dart';
import '../features/test/screens/test_taking_screen.dart';
import '../../core/models/test_template.dart';
import '../../core/models/question_bank_item.dart';

final class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: kDebugMode,
    refreshListenable: _AuthRefreshListenable(),
    redirect: (context, state) {
      final authStatus = AuthService.currentStatus;
      final location = state.matchedLocation;

      const splashPath = '/';
      const loginPath = '/login';
      const signupPath = '/signup';
      const homePath = '/home';

      final isAuthRoute = location == loginPath || location == signupPath;
      final isSplash = location == splashPath;

      switch (authStatus) {
        case AuthStatus.unknown:
          return isSplash ? null : splashPath;

        case AuthStatus.unauthenticated:
          return isAuthRoute ? null : loginPath;

        case AuthStatus.authenticated:
          if (isSplash) return homePath;
          if (isAuthRoute) return homePath;
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const AuthScreen(startWithSignup: true),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const AppShell(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'avatar',
            name: 'avatar-viewer',
            builder: (context, state) {
              final params = state.uri.queryParameters;
              return AvatarViewerScreen(
                avatarUrl: params['url'],
                initials: params['initials'] ?? '?',
              );
            },
          ),
          GoRoute(
            path: ':userId',
            name: 'user-profile',
            builder: (context, state) => ProfileScreen(
              userId: state.pathParameters['userId'],
              initialProfile: state.extra is Profile
                  ? state.extra as Profile
                  : null,
            ),
            routes: [
              GoRoute(
                path: 'connections',
                name: 'user-connections',
                builder: (context, state) {
                  final extra = state.extra;
                  return UserConnectionsScreen(
                    userId: state.pathParameters['userId']!,
                    userName: extra is String ? extra : null,
                    initialTab: state.uri.queryParameters['tab'] ?? 'followers',
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/refer-and-earn',
        name: 'refer-and-earn',
        builder: (context, state) => const ReferAndEarnScreen(),
      ),
      GoRoute(
        path: '/founder-profile/:userId',
        name: 'founder-profile',
        builder: (context, state) => ProfileScreen(
          userId: state.pathParameters['userId'],
          initialProfile: state.extra is Profile
              ? state.extra as Profile
              : null,
        ),
      ),
      GoRoute(
        path: '/community',
        name: 'community',
        builder: (context, state) => const CommunityHubScreen(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) => const AboutAppScreen(),
      ),
      GoRoute(
        path: '/performance',
        name: 'performance',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Performance')),
          body: const PerformanceScreen(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsHubScreen(),
      ),
      GoRoute(
        path: '/my-uploads',
        name: 'my-uploads',
        builder: (context, state) => const MyUploadsScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        name: 'notification-settings',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/leaderboard',
        name: 'leaderboard',
        builder: (context, state) => const LeaderboardHubScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // ── Study System V1 (Phase 4) ──
      GoRoute(
        path: '/study',
        name: 'study-home',
        builder: (context, state) => const StudyHomeScreen(),
        routes: [
          GoRoute(
            path: 'subject/:subjectId',
            name: 'study-subject-chapters',
            builder: (context, state) => SubjectChaptersScreen(
              subjectId: state.pathParameters['subjectId']!,
            ),
          ),
          GoRoute(
            path: 'chapter/:chapterId',
            name: 'study-chapter-hub',
            builder: (context, state) {
              final chapterId = state.pathParameters['chapterId']!;
              final initialTab =
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
              return ChapterHubScreen(
                chapterId: chapterId,
                initialTab: initialTab,
              );
            },
          ),
          GoRoute(
            path: 'topic/:topicId',
            name: 'study-topic-theory',
            builder: (context, state) {
              final topicId = state.pathParameters['topicId']!;
              final chapterId =
                  state.uri.queryParameters['chapterId'] ??
                  (state.extra as String? ?? '');
              return TopicTheoryScreen(topicId: topicId, chapterId: chapterId);
            },
          ),
          GoRoute(
            path: 'topic/:topicId/practice',
            name: 'study-topic-practice',
            builder: (context, state) {
              final topicId = state.pathParameters['topicId']!;
              final extraMap = state.extra is Map<String, dynamic>
                  ? state.extra as Map<String, dynamic>
                  : null;
              final chapterId =
                  state.uri.queryParameters['chapterId'] ??
                  (extraMap?['chapterId'] as String?) ??
                  '';
              final topicTitle =
                  state.uri.queryParameters['topicTitle'] ??
                  (extraMap?['topicTitle'] as String?);
              final chapterTitle =
                  state.uri.queryParameters['chapterTitle'] ??
                  (extraMap?['chapterTitle'] as String?);
              final subjectTitle =
                  state.uri.queryParameters['subjectTitle'] ??
                  (extraMap?['subjectTitle'] as String?);
              final subjectId =
                  state.uri.queryParameters['subjectId'] ??
                  (extraMap?['subjectId'] as String?);

              return TopicPracticeScreen(
                topicId: topicId,
                chapterId: chapterId,
                topicTitle: topicTitle,
                chapterTitle: chapterTitle,
                subjectTitle: subjectTitle,
                subjectId: subjectId,
              );
            },
          ),
        ],
      ),
      // Calendar V1: routines + scheduled tests on one month grid (read-only).
      GoRoute(
        path: '/calendar',
        name: 'calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/subjects',
        name: 'subjects',
        redirect: (context, state) => '/study',
      ),
      GoRoute(
        path: '/subjects/:subjectId/syllabus',
        name: 'syllabus',
        redirect: (context, state) {
          final subjectId = state.pathParameters['subjectId'];
          return subjectId != null ? '/study/subject/$subjectId' : '/study';
        },
      ),
      GoRoute(
        path: '/subjects/:subjectId/syllabus/:nodeId',
        name: 'syllabus-detail',
        builder: (context, state) {
          final subjectId = state.pathParameters['subjectId']!;
          final nodeId = state.pathParameters['nodeId']!;
          final nodeName = state.extra as String? ?? 'Topics';
          return SyllabusDetailScreen(
            subjectId: subjectId,
            parentNodeId: nodeId,
            nodeName: nodeName,
          );
        },
      ),
      GoRoute(
        path: '/subjects/:subjectId/nodes/:nodeId/materials',
        name: 'materials',
        builder: (context, state) {
          final nodeId = state.pathParameters['nodeId']!;
          final nodeName = state.extra as String? ?? 'Materials';
          return MaterialListScreen(nodeId: nodeId, nodeName: nodeName);
        },
      ),
      GoRoute(
        path: '/materials/:materialId',
        name: 'material-detail',
        builder: (context, state) {
          final materialId = state.pathParameters['materialId']!;
          final materialTitle = state.extra as String? ?? 'Material';
          return MaterialDetailScreen(
            materialId: materialId,
            materialTitle: materialTitle,
          );
        },
      ),
      // ── Group Hub (G1): routes carry ids only ──
      GoRoute(
        path: '/groups',
        name: 'group-list',
        builder: (context, state) => const GroupListScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: 'group-create',
            builder: (context, state) => const GroupCreateScreen(),
          ),
          // Declared before ':groupId' so the literal wins the match.
          GoRoute(
            path: 'join',
            name: 'group-join',
            builder: (context, state) =>
                const GroupListScreen(openJoinSheet: true),
          ),
          GoRoute(
            path: ':groupId',
            name: 'group-hub',
            builder: (context, state) =>
                GroupChatScreen(groupId: state.pathParameters['groupId']!),
            routes: [
              GoRoute(
                path: 'info',
                name: 'group-info',
                builder: (context, state) =>
                    GroupInfoScreen(groupId: state.pathParameters['groupId']!),
              ),
              GoRoute(
                path: 'chat',
                name: 'group-chat',
                builder: (context, state) =>
                    GroupChatScreen(groupId: state.pathParameters['groupId']!),
              ),
              GoRoute(
                path: 'discussion',
                name: 'group-discussion',
                builder: (context, state) {
                  final controller = state.extra;
                  if (controller is GroupHubController) {
                    return GroupChatScreen(
                      groupId: state.pathParameters['groupId']!,
                      controller: controller,
                    );
                  }
                  return GroupChatScreen(
                    groupId: state.pathParameters['groupId']!,
                  );
                },
              ),
              GoRoute(
                path: 'members',
                name: 'group-members',
                builder: (context, state) => GroupMembersScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
              // G16: the caller's own notifications for this group.
              GoRoute(
                path: 'notifications',
                name: 'group-notifications',
                builder: (context, state) => GroupNotificationsScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
              GoRoute(
                path: 'settings',
                name: 'group-settings',
                builder: (context, state) => GroupSettingsScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
              // G10: group test management (ids only).
              GoRoute(
                path: 'tests',
                name: 'group-tests',
                builder: (context, state) =>
                    GroupTestsScreen(groupId: state.pathParameters['groupId']!),
                routes: [
                  // G11: group test results.
                  GoRoute(
                    path: ':testId/results',
                    name: 'group-test-results',
                    builder: (context, state) => GroupTestResultsScreen(
                      testId: state.pathParameters['testId']!,
                      groupId: state.pathParameters['groupId']!,
                    ),
                    routes: [
                      // G12: group test leaderboard.
                      GoRoute(
                        path: 'leaderboard',
                        name: 'group-test-leaderboard',
                        builder: (context, state) => GroupLeaderboardScreen(
                          testId: state.pathParameters['testId']!,
                          groupId: state.pathParameters['groupId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // ── Test system (original, mature) ──
      GoRoute(
        path: '/tests',
        name: 'test-listing',
        builder: (context, state) {
          final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return TestListingScreen(initialTab: tab);
        },
        routes: [
          GoRoute(
            path: 'drafts',
            name: 'test-listing-drafts',
            builder: (context, state) => const TestListingScreen(initialTab: 3),
          ),
          // Peer Challenge (0061): join a host's session by 6-digit PIN.
          // Declared before ':testId' so the literal wins the match.
          GoRoute(
            path: 'join',
            name: 'challenge-join',
            builder: (context, state) => const ChallengeJoinScreen(),
          ),
          // G19: test templates
          GoRoute(
            path: 'templates',
            name: 'template-listing',
            builder: (context, state) => const TemplateListingScreen(),
            routes: [
              GoRoute(
                path: 'create',
                name: 'template-create',
                builder: (context, state) => const TemplateFormScreen(),
              ),
              GoRoute(
                path: ':templateId/edit',
                name: 'template-edit',
                builder: (context, state) => TemplateFormScreen(
                  templateId: state.pathParameters['templateId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'create',
            name: 'test-create',
            builder: (context, state) {
              final s = state.uri.queryParameters['source'];
              final extra = state.extra;

              TestTemplate? template;
              Map<String, dynamic>? prefill;

              if (extra is TestTemplate) {
                template = extra;
              } else if (extra is Map<String, dynamic>) {
                prefill = extra;
              }

              QuestionSource? source;
              if (prefill != null &&
                  prefill['initialSource'] is QuestionSource) {
                source = prefill['initialSource'] as QuestionSource;
              } else if (s != null) {
                source = QuestionSource.values
                    .cast<QuestionSource?>()
                    .firstWhere((v) => v?.name == s, orElse: () => null);
              }

              return TestCreationScreen(
                initialGroupId: state.uri.queryParameters['group'],
                initialSource: source,
                template: template,
                prefillTitle: prefill?['prefillTitle'] as String?,
                prefillSubjectId: prefill?['prefillSubjectId'] as String?,
                prefillChapterId: prefill?['prefillChapterId'] as String?,
                availableQuestionCount:
                    prefill?['availableQuestionCount'] as int?,
                defaultMode: prefill?['defaultMode'] as String?,
              );
            },
          ),
          GoRoute(
            path: 'create/document-import',
            name: 'document-import',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return DocumentUploadScreen(
                groupId: extra?['groupId'] as String?,
              );
            },
          ),
          GoRoute(
            path: 'create/ai-generate',
            name: 'ai-generate',
            builder: (context, state) {
              final prefill = state.extra as AiGenerationPrefill?;
              return AiGenerationScreen(prefill: prefill);
            },
          ),
          // Shared multi-page camera capture (Phase 3) — used by both Via
          // Document/File and Create by AI's "Take Photos" entry point.
          GoRoute(
            path: 'create/camera-capture',
            name: 'camera-capture',
            builder: (context, state) => const CameraCaptureScreen(),
          ),
          GoRoute(
            path: ':testId',
            name: 'test-detail',
            builder: (context, state) =>
                TestDetailScreen(testId: state.pathParameters['testId']!),
            routes: [
              GoRoute(
                path: 'edit',
                name: 'test-edit',
                builder: (context, state) =>
                    TestCreationScreen(testId: state.pathParameters['testId']!),
              ),
            ],
          ),
        ],
      ),
      // Legacy paths kept as redirects so old links keep working.
      GoRoute(path: '/create-test', redirect: (_, _) => '/tests/create'),
      GoRoute(
        path: '/edit-test/:testId',
        redirect: (_, state) => '/tests/${state.pathParameters['testId']}/edit',
      ),
      GoRoute(
        path: '/attempts/:attemptId/take',
        name: 'attempt-take',
        builder: (context, state) => TestTakingScreen(
          attemptId: state.pathParameters['attemptId']!,
          testId: state.uri.queryParameters['test'] ?? '',
          accessCode: state.uri.queryParameters['code'],
          challengeSessionId: state.uri.queryParameters['challenge'],
        ),
      ),
      // ── Peer Challenge (0061): waiting room + merit list ──
      GoRoute(
        path: '/challenge/:sessionId/waiting-room',
        name: 'challenge-waiting-room',
        builder: (context, state) {
          final extra = state.extra;
          return ChallengeWaitingRoomScreen(
            sessionId: state.pathParameters['sessionId'],
            controller: extra is ChallengeController ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/challenge/:sessionId/merit-list',
        name: 'challenge-merit-list',
        builder: (context, state) => ChallengeMeritListScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/attempts/:attemptId/result',
        name: 'attempt-result',
        builder: (context, state) => TestResultScreen(
          attemptId: state.pathParameters['attemptId']!,
        ),
      ),
      GoRoute(
        path: '/attempts/:attemptId/review',
        name: 'attempt-review',
        builder: (context, state) =>
            QuestionReviewScreen(attemptId: state.pathParameters['attemptId']!),
      ),
      // ── Routine V1 ──
      GoRoute(
        path: '/routine',
        name: 'routine-list',
        builder: (context, state) => const RoutineListScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: 'routine-create',
            builder: (context, state) => const RoutineCreateScreen(),
          ),
          // Static segment must precede ':routineId' so it is not captured.
          GoRoute(
            path: 'history',
            name: 'routine-history',
            builder: (context, state) => RoutineHistoryScreen(
              routineId: state.uri.queryParameters['routine'],
            ),
          ),
          GoRoute(
            path: ':routineId',
            name: 'routine-detail',
            builder: (context, state) => RoutineDetailScreen(
              routineId: state.pathParameters['routineId']!,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                name: 'routine-edit',
                builder: (context, state) => RoutineCreateScreen(
                  routineId: state.pathParameters['routineId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      // ── Question Bank (R7) ──
      GoRoute(
        path: '/question-bank',
        name: 'question-bank',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final selectionMode = extra?['selectionMode'] as bool? ?? false;
          final onSelectionConfirmed =
              extra?['onSelectionConfirmed']
                  as ValueChanged<List<QuestionBankItem>>?;
          final initialFilter =
              extra?['initialFilter'] as QuestionBankFilter?;
          return QuestionBankScreen(
            selectionMode: selectionMode,
            onSelectionConfirmed: onSelectionConfirmed,
            initialFilter: initialFilter,
          );
        },
        routes: [
          GoRoute(
            path: ':questionId',
            name: 'question-bank-detail',
            builder: (context, state) => QuestionBankDetailScreen(
              questionId: state.pathParameters['questionId']!,
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The page "${state.matchedLocation}" does not exist.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AuthRefreshListenable extends ChangeNotifier {
  late final StreamSubscription<AuthStatus> _authSubscription;
  late final StreamSubscription<ProfileStatus> _profileSubscription;

  _AuthRefreshListenable() {
    _authSubscription = AuthService.authStatusStream.listen((_) {
      notifyListeners();
    });
    _profileSubscription = ProfileService.statusStream.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _profileSubscription.cancel();
    super.dispose();
  }
}
