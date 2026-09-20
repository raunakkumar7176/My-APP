import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/services/auth_service.dart';
import '../core/services/profile_service.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/group/screens/group_create_screen.dart';
import '../features/group/screens/group_hub_screen.dart';
import '../features/group/screens/group_leaderboard_screen.dart';
import '../features/group/screens/group_list_screen.dart';
import '../features/group/screens/group_members_screen.dart';
import '../features/group/screens/group_notifications_screen.dart';
import '../features/group/screens/group_settings_screen.dart';
import '../features/group/screens/group_test_results_screen.dart';
import '../features/group/screens/group_tests_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/study/material_detail_screen.dart';
import '../features/study/material_list_screen.dart';
import '../features/study/subject_list_screen.dart';
import '../features/study/syllabus_detail_screen.dart';
import '../features/study/syllabus_screen.dart';
import '../features/test/screens/question_bank_screen.dart';
import '../features/test/screens/question_bank_detail_screen.dart';
import '../features/test/screens/question_review_screen.dart';
import '../features/test/screens/test_creation_screen.dart';
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
    debugLogDiagnostics: true,
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
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/subjects',
        name: 'subjects',
        builder: (context, state) => const SubjectListScreen(),
      ),
      GoRoute(
        path: '/subjects/:subjectId/syllabus',
        name: 'syllabus',
        builder: (context, state) {
          final subjectId = state.pathParameters['subjectId']!;
          final subjectName = state.extra as String?;
          return SyllabusScreen(subjectId: subjectId, subjectName: subjectName);
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
                GroupHubScreen(groupId: state.pathParameters['groupId']!),
            routes: [
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
                builder: (context, state) => GroupTestsScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
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
      // ── Test system (R4 restart): routes carry ids only ──
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
              final template = state.extra as TestTemplate?;
              return TestCreationScreen(
                initialGroupId: state.uri.queryParameters['group'],
                initialSource: QuestionSource.values
                    .cast<QuestionSource?>()
                    .firstWhere((v) => v?.name == s, orElse: () => null),
                template: template,
              );
            },
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
        ),
      ),
      GoRoute(
        path: '/attempts/:attemptId/result',
        name: 'attempt-result',
        builder: (context, state) =>
            TestResultScreen(attemptId: state.pathParameters['attemptId']!),
      ),
      GoRoute(
        path: '/attempts/:attemptId/review',
        name: 'attempt-review',
        builder: (context, state) =>
            QuestionReviewScreen(attemptId: state.pathParameters['attemptId']!),
      ),
      // ── Question Bank (R7) ──
      GoRoute(
        path: '/question-bank',
        name: 'question-bank',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final selectionMode = extra?['selectionMode'] as bool? ?? false;
          final onSelectionConfirmed =
              extra?['onSelectionConfirmed'] as ValueChanged<List<QuestionBankItem>>?;
          return QuestionBankScreen(
            selectionMode: selectionMode,
            onSelectionConfirmed: onSelectionConfirmed,
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
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
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
              onPressed: () => context.go('/'),
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
