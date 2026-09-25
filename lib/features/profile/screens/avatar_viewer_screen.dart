import 'package:flutter/material.dart';

/// Full-screen profile photo viewer. Supports pinch-to-zoom and
/// double-tap-to-zoom via [InteractiveViewer] (already in the Flutter SDK —
/// no new dependency needed). Shows a graceful default-avatar state
/// instead of a broken-image icon when there is no photo, and a graceful
/// error state if the network image fails to load (e.g. a stale/expired
/// URL) rather than crashing.
class AvatarViewerScreen extends StatefulWidget {
  const AvatarViewerScreen({
    required this.initials,
    this.avatarUrl,
    super.key,
  });

  final String? avatarUrl;
  final String initials;

  @override
  State<AvatarViewerScreen> createState() => _AvatarViewerScreenState();
}

class _AvatarViewerScreenState extends State<AvatarViewerScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    const zoomed = 2.5;
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;
    final matrix = Matrix4.identity()
      ..translateByDouble(-position.dx * (zoomed - 1), -position.dy * (zoomed - 1), 0, 1)
      ..scaleByDouble(zoomed, zoomed, zoomed, 1);
    _transformController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = widget.avatarUrl != null && widget.avatarUrl!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          key: const Key('avatar_viewer_close'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Center(
          key: const Key('avatar_viewer_body'),
          child: hasPhoto ? _buildZoomableImage(widget.avatarUrl!) : _buildDefaultAvatar(),
        ),
      ),
    );
  }

  Widget _buildZoomableImage(String url) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1,
        maxScale: 4,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          cacheWidth: (MediaQuery.sizeOf(context).width *
                  MediaQuery.devicePixelRatioOf(context))
              .round(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Colors.white70),
            );
          },
          errorBuilder: (context, error, stackTrace) => Padding(
            key: const Key('avatar_viewer_error'),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64),
                const SizedBox(height: 16),
                Text(
                  "Couldn't load this photo.",
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Column(
      key: const Key('avatar_viewer_default'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 96,
          backgroundColor: Colors.white24,
          child: Text(
            widget.initials,
            style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        const Text('No profile photo yet', style: TextStyle(color: Colors.white70)),
      ],
    );
  }
}
