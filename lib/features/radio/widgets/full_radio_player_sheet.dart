import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../state/radio_player_controller.dart';

const _speedOptions = [1.0, 1.25, 1.5, 2.0];

/// Expanded, podcast-style player — opened by tapping [MiniRadioPlayerBar].
class FullRadioPlayerSheet extends StatefulWidget {
  const FullRadioPlayerSheet({super.key});

  @override
  State<FullRadioPlayerSheet> createState() => _FullRadioPlayerSheetState();
}

class _FullRadioPlayerSheetState extends State<FullRadioPlayerSheet> {
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
    final theme = Theme.of(context);
    final track = _controller.currentTrack;

    if (track == null) {
      return const SizedBox(height: 200, child: Center(child: Text('Nothing playing.')));
    }

    final progress = _controller.totalTracks == 0
        ? 0.0
        : (_controller.currentIndex + 1) / _controller.totalTracks;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainerLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _controller.sourceTitle ?? 'Radio Revision',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              Icon(Icons.graphic_eq_rounded, size: 64, color: AppColors.primaryLight.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(
                track.question.question,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (track.question.options != null)
                for (var i = 0; i < track.question.options!.length; i++)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: track.correctOption == i
                          ? AppColors.success.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: track.correctOption == i ? Border.all(color: AppColors.success) : null,
                    ),
                    child: Text(track.question.options![i].text),
                  ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 4),
              Text('Q ${_controller.currentIndex + 1}/${_controller.totalTracks}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: _controller.currentIndex > 0 ? _controller.previous : null,
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(18),
                    ),
                    onPressed: _controller.togglePlayPause,
                    child: Icon(
                      _controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: _controller.next,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in _speedOptions)
                    ChoiceChip(
                      label: Text('${s}x'),
                      selected: _controller.speed == s,
                      onSelected: (_) => _controller.setSpeed(s),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hands-Free Drill'),
                subtitle: const Text('33 second pause after the question before the answer.'),
                value: _controller.handsFreeMode,
                onChanged: _controller.setHandsFreeMode,
              ),
            ],
          ),
        );
      },
    );
  }
}
