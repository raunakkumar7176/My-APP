import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../domain/app_tutorial.dart';

/// Plays a tutorial video inside the app (no jump to the YouTube app, no
/// recommendations/shorts feed to get distracted by) via a bottom sheet.
Future<void> showTutorialVideoSheet(BuildContext context, AppTutorial tutorial) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    builder: (_) => _TutorialVideoSheet(tutorial: tutorial),
  );
}

class _TutorialVideoSheet extends StatefulWidget {
  const _TutorialVideoSheet({required this.tutorial});

  final AppTutorial tutorial;

  @override
  State<_TutorialVideoSheet> createState() => _TutorialVideoSheetState();
}

class _TutorialVideoSheetState extends State<_TutorialVideoSheet> {
  late final YoutubePlayerController _controller = YoutubePlayerController(
    initialVideoId: widget.tutorial.youtubeVideoId,
    flags: const YoutubePlayerFlags(autoPlay: true, mute: false),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            YoutubePlayer(controller: _controller, showVideoProgressIndicator: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Text(
                widget.tutorial.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
