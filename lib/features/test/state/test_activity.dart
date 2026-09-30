import 'package:flutter/foundation.dart';

/// Cross-screen "a test was just submitted" signal, same pattern as
/// `RoutineController.revision`. `AppShell` keeps all 5 tabs alive via
/// `IndexedStack`, so a screen's `initState`/load only ever runs once per
/// app session — without this, Dashboard's Performance Snapshot / Recent
/// Tests and the Performance tab stay stale after finishing a test
/// elsewhere until the user pulls to refresh. [bump] is called once, right
/// where `rpc_submit_and_score_test` actually succeeds
/// (attempt_repository.dart); listeners reload from there.
final class TestActivity {
  TestActivity._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void bump() => revision.value++;
}
