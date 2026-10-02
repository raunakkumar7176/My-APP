import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/tutorial_repository.dart';
import '../domain/app_tutorial.dart';
import 'tutorial_video_sheet.dart';

/// A small "? Video Dekhein" AppBar action that jumps straight to this
/// screen's own tutorial video — the whole point of "contextual help": the
/// student never has to go find the Tutorials screen and search.
///
/// Picks the first active video in [category]; if none is loaded yet (or
/// none exists), it falls back to opening the full Tutorials list filtered
/// to that category instead of doing nothing.
class TutorialHelpButton extends StatelessWidget {
  const TutorialHelpButton({required this.category, super.key});

  final TutorialCategory category;

  Future<void> _onTap(BuildContext context) async {
    final tutorials = await const SupabaseTutorialRepository().all();
    final inCategory = tutorials.where((t) => t.category == category).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    if (!context.mounted) return;
    if (inCategory.isNotEmpty) {
      await showTutorialVideoSheet(context, inCategory.first);
    } else {
      context.push('/tutorials');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Video Dekhein',
      icon: const Icon(Icons.help_outline_rounded),
      onPressed: () => _onTap(context),
    );
  }
}
