import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file in this directory tree. Without a mocked
/// shared_preferences channel, any widget test that touches
/// `SharedPreferences.getInstance()` (e.g. `GroupListController.load()`'s
/// "hidden groups" persistence) either throws `MissingPluginException` or,
/// worse, never resolves at all — silently costing each such test a multi-
/// second internal timeout, or hanging it outright. One mock here covers
/// every test file instead of each one remembering to call
/// `SharedPreferences.setMockInitialValues({})` itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
