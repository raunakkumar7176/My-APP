// Route audit (final remediation): every location the app pushes must resolve
// to a registered GoRoute. Found on audit: the results screen pushed
// `/groups/:g/tests/:t/leaderboard` while the route is registered under
// `/groups/:g/tests/:t/results/leaderboard` (a dead link on device).
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/app/app_router.dart';

/// Flattens the route tree into full path templates.
List<String> _paths(List<RouteBase> routes, [String prefix = '']) {
  final out = <String>[];
  for (final r in routes) {
    if (r is GoRoute) {
      final full = r.path.startsWith('/')
          ? r.path
          : '${prefix == '/' ? '' : prefix}/${r.path}';
      out.add(full);
      out.addAll(_paths(r.routes, full));
    } else {
      out.addAll(_paths(r.routes, prefix));
    }
  }
  return out;
}

bool _matches(String template, String location) {
  final t = template.split('/');
  final l = location.split('?').first.split('/');
  if (t.length != l.length) return false;
  for (var i = 0; i < t.length; i++) {
    if (t[i].startsWith(':')) continue;
    if (t[i] != l[i]) return false;
  }
  return true;
}

void main() {
  final templates = _paths(AppRouter.router.configuration.routes);

  test('route table contains every Group Hub and R4 screen', () {
    const required = [
      '/login',
      '/signup',
      '/home',
      '/profile',
      '/subjects',
      '/groups',
      '/groups/create',
      '/groups/join',
      '/groups/:groupId',
      '/groups/:groupId/members',
      '/groups/:groupId/notifications',
      '/groups/:groupId/settings',
      '/groups/:groupId/tests',
      '/groups/:groupId/tests/:testId/results',
      '/groups/:groupId/tests/:testId/results/leaderboard',
      '/tests',
      '/tests/drafts',
      '/tests/create',
      '/tests/:testId',
      '/tests/:testId/edit',
      '/attempts/:attemptId/take',
      '/attempts/:attemptId/result',
      '/attempts/:attemptId/review',
    ];
    for (final r in required) {
      expect(templates, contains(r), reason: r);
    }
  });

  test(
    'every location the app navigates to resolves to a registered route',
    () {
      // Concrete locations as built by the screens (ids substituted).
      const used = [
        '/',
        '/groups',
        '/groups/create',
        '/groups/g1',
        '/groups/g1/members',
        '/groups/g1/settings',
        '/groups/g1/notifications',
        '/groups/g1/tests',
        '/groups/g1/tests/t1/results',
        '/groups/g1/tests/t1/results/leaderboard',
        '/tests',
        '/tests/drafts',
        '/tests/create',
        '/tests/create?group=g1',
        '/tests/create?source=ai',
        '/tests/t1',
        '/tests/t1/edit',
        '/attempts/a1/take?test=t1',
        '/attempts/a1/result',
        '/attempts/a1/review',
        '/subjects',
        '/subjects/s1/syllabus',
        '/profile',
      ];
      for (final loc in used) {
        expect(
          templates.any((t) => _matches(t, loc)),
          isTrue,
          reason: '$loc has no registered route',
        );
      }
      // The former dead link must not be considered valid.
      expect(
        templates.any((t) => _matches(t, '/groups/g1/tests/t1/leaderboard')),
        isFalse,
      );
    },
  );
}
