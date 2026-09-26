import 'package:flutter/material.dart';

import '../state/group_hub_controller.dart';
import 'group_chat_screen.dart';

export 'group_chat_screen.dart';

/// Backward-compatible wrapper for [GroupChatScreen] when provided a shared [GroupHubController].
class GroupDiscussionScreen extends StatelessWidget {
  const GroupDiscussionScreen({required this.controller, super.key});

  final GroupHubController controller;

  @override
  Widget build(BuildContext context) {
    return GroupChatScreen(groupId: controller.groupId, controller: controller);
  }
}
