import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../state/radio_player_controller.dart';
import 'full_radio_player_sheet.dart';

/// Persistent Spotify-style mini bar, shown globally (mounted at the app
/// root, above every screen) whenever [RadioPlayerController.instance] has
/// an active session — so playback survives navigating to any other
/// screen, not just the one that started it.
class MiniRadioPlayerBar extends StatefulWidget {
  const MiniRadioPlayerBar({super.key});

  @override
  State<MiniRadioPlayerBar> createState() => _MiniRadioPlayerBarState();
}

class _MiniRadioPlayerBarState extends State<MiniRadioPlayerBar> {
  final _controller = RadioPlayerController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isActive) return const SizedBox.shrink();
    final track = _controller.currentTrack;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        child: InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const FullRadioPlayerSheet(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.graphic_eq_rounded, color: AppColors.primaryLight, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Q ${_controller.currentIndex + 1}/${_controller.totalTracks}'
                        '${track != null ? ': ${track.question.question}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        _controller.sourceTitle ?? 'Radio Revision',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: _controller.togglePlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: _controller.next,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _controller.stop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
