import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/app_tutorial.dart';

/// Opens a tutorial video in the YouTube app (or the browser if it isn't
/// installed).
///
/// Originally played in-app via `youtube_player_flutter`, but that package
/// transitively pulls in `flutter_inappwebview_android` 1.1.3, whose own
/// build.gradle calls an AGP API this project's Android Gradle Plugin
/// (9.1.0) outright rejects at build time -- no newer
/// flutter_inappwebview_android version was resolvable against the rest of
/// this project's dependency graph, and downgrading AGP project-wide to
/// chase one video widget wasn't a trade worth making. An external launch
/// loses the "never leave the app" nicety, but every build in this project
/// was failing because of it.
Future<void> showTutorialVideoSheet(BuildContext context, AppTutorial tutorial) async {
  final uri = Uri.parse('https://www.youtube.com/watch?v=${tutorial.youtubeVideoId}');
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the video.')),
    );
  }
}
