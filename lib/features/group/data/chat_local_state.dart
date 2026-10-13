import 'package:shared_preferences/shared_preferences.dart';

/// Per-device, per-group local chat state — never synced to the server,
/// never visible to other members. Backs two client-only features that
/// have no server counterpart:
///   * the unread divider: when this device last opened the chat, so a
///     "New messages" line can be drawn once, honestly, without a new
///     backend read of `message_reads.last_read_at` (which this client
///     never reads today, only writes via `markGroupRead`);
///   * "Clear chat": hides messages older than a point in time, for this
///     user on this device only — the server's history (and every other
///     member's view) is untouched.
class ChatLocalState {
  const ChatLocalState();

  String _lastOpenedKey(String groupId) => 'chat_last_opened_$groupId';
  String _clearedBeforeKey(String groupId) => 'chat_cleared_before_$groupId';

  Future<DateTime?> lastOpenedAt(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_lastOpenedKey(groupId));
    return iso == null ? null : DateTime.tryParse(iso);
  }

  Future<void> setLastOpenedAt(String groupId, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastOpenedKey(groupId), at.toIso8601String());
  }

  Future<DateTime?> clearedBefore(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_clearedBeforeKey(groupId));
    return iso == null ? null : DateTime.tryParse(iso);
  }

  Future<void> clearChat(String groupId, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clearedBeforeKey(groupId), at.toIso8601String());
  }
}
