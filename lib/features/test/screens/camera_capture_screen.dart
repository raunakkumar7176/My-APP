import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/services/camera_capture_service.dart';
import '../state/camera_capture_controller.dart';

/// Multi-page camera capture (Phase 3). Returns the ordered page bytes via
/// `context.pop()` when the user taps Done, or null if they back out.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({this.controller, this.title, super.key});

  final CameraCaptureController? controller;

  /// e.g. "Take Photos for AI" vs "Take Photos" — same screen either way.
  final String? title;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  late final CameraCaptureController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? CameraCaptureController();
    _c.addListener(_onChanged);
    if (_c.pages.isEmpty) _c.captureOne();
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final pending = _c.pendingQualityWarningIndex;
    if (pending != null) _showQualityDialog(pending);
  }

  Future<void> _showQualityDialog(int index) async {
    final reason = switch (_c.pages[index].quality) {
      PageQuality.tooDark => 'This page looks very dark.',
      PageQuality.blank => 'This page looks blank or out of focus.',
      PageQuality.unreadableFormat => 'This photo could not be read.',
      PageQuality.ok => 'This page may be difficult to read.',
    };
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const Key('camera_quality_dialog'),
        icon: const Icon(Icons.warning_amber, color: AppColors.warning, size: 40),
        title: const Text('This page may be difficult to read'),
        content: Text(reason),
        actions: [
          TextButton(
            key: const Key('camera_quality_retake'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.retakePending();
            },
            child: const Text('Retake'),
          ),
          FilledButton(
            key: const Key('camera_quality_keep'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.keepPendingAnyway();
            },
            child: const Text('Keep Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    if (_c.pages.isEmpty) return;
    final bytes = await _c.finish();
    if (mounted) context.pop<List<Uint8List>>(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Take Photos'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          _statusBar(),
          Expanded(child: _pagesGrid()),
          if (_c.errorMessage != null) _errorBanner(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('camera_add_page'),
                  onPressed: _c.isBusy || _c.isAtMax ? null : _c.captureOne,
                  icon: _c.isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: Text(_c.pages.isEmpty ? 'Take First Photo' : 'Add Page'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('camera_done'),
                onPressed: _c.pages.isEmpty ? null : _finish,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        _c.pages.isEmpty
            ? 'No pages yet'
            : '${_c.pages.length} page${_c.pages.length == 1 ? '' : 's'} added'
                  '${_c.isAtMax ? ' · maximum reached' : ''}',
        key: const Key('camera_page_count'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }

  Widget _errorBanner() {
    return MaterialBanner(
      key: const Key('camera_error'),
      content: Text(_c.errorMessage!),
      leading: const Icon(Icons.error_outline, color: AppColors.error),
      actions: [
        TextButton(onPressed: _c.captureOne, child: const Text('Try Again')),
      ],
    );
  }

  Widget _pagesGrid() {
    if (_c.pages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Take a photo of the first page to get started.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: _c.pages.length,
      itemBuilder: (context, i) => _pageTile(i),
    );
  }

  Widget _pageTile(int index) {
    final page = _c.pages[index];
    final theme = Theme.of(context);
    return Card(
      key: Key('camera_page_$index'),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RotatedBox(
            quarterTurns: page.rotationQuarterTurns,
            child: Image.memory(page.bytes, fit: BoxFit.cover),
          ),
          if (page.quality != PageQuality.ok)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Low quality',
                  style: TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${index + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('camera_rotate_$index'),
                        icon: const Icon(Icons.rotate_right, color: Colors.white, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _c.rotatePage(index),
                      ),
                      IconButton(
                        key: Key('camera_retake_$index'),
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _c.retake(index),
                      ),
                      IconButton(
                        key: Key('camera_delete_$index'),
                        icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _c.deletePage(index),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
