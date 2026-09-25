import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/services/document_service.dart';
import '../state/my_uploads_controller.dart';

/// "My Uploaded Documents": lists every source file the current user has
/// uploaded via Via Document/File (Storage object + metadata row), lets
/// them delete one (with confirmation, Storage first then the DB row), and
/// offers a "Clean up orphaned files" action for Storage objects a partial
/// failure left without a metadata row. Read-only history — it does not
/// feed back into test creation.
class MyUploadsScreen extends StatefulWidget {
  const MyUploadsScreen({this.controller, super.key});

  /// Injection point for tests; production constructs its own.
  final MyUploadsController? controller;

  @override
  State<MyUploadsScreen> createState() => _MyUploadsScreenState();
}

class _MyUploadsScreenState extends State<MyUploadsScreen> {
  late final MyUploadsController _c;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _c = widget.controller ?? MyUploadsController();
    _c.addListener(_onChanged);
    _c.load();
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_ownsController) _c.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _confirmDelete(UploadedDocumentRecord doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text(
          '"${doc.fileName}" will be permanently deleted from storage. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await _c.delete(doc);
    if (!mounted) return;
    if (error != null) {
      _snack(error, error: true);
    } else {
      _snack('File deleted.');
    }
  }

  Future<void> _cleanupOrphans() async {
    final error = await _c.cleanupOrphans();
    if (!mounted) return;
    if (error != null) {
      _snack(error, error: true);
    } else {
      final count = _c.lastCleanupCount ?? 0;
      _snack(
        count == 0
            ? 'No orphaned files found.'
            : 'Removed $count orphaned file${count == 1 ? '' : 's'}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Uploaded Documents'),
        actions: [
          IconButton(
            key: const Key('my_uploads_cleanup'),
            tooltip: 'Clean up orphaned files',
            onPressed: _c.isCleaningUp ? null : _cleanupOrphans,
            icon: _c.isCleaningUp
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_c.state) {
      case MyUploadsLoadState.idle:
      case MyUploadsLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case MyUploadsLoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text(_c.errorMessage ?? 'Something went wrong', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _c.load, child: const Text('Retry')),
              ],
            ),
          ),
        );
      case MyUploadsLoadState.loaded:
        if (_c.documents.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey.shade500),
                  const SizedBox(height: 16),
                  const Text('No uploaded files yet.', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _c.load,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _c.documents.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _DocumentTile(
              key: ValueKey('my_upload_${_c.documents[i].id}'),
              doc: _c.documents[i],
              isDeleting: _c.isDeleting(_c.documents[i].id),
              onDelete: () => _confirmDelete(_c.documents[i]),
            ),
          ),
        );
    }
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    super.key,
    required this.doc,
    required this.isDeleting,
    required this.onDelete,
  });

  final UploadedDocumentRecord doc;
  final bool isDeleting;
  final VoidCallback onDelete;

  IconData get _icon {
    final ext = doc.fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String get _sizeLabel {
    final bytes = doc.fileSize;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_icon),
        title: Text(doc.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$_sizeLabel · ${doc.status}'),
        trailing: isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                key: Key('my_upload_delete_${doc.id}'),
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: onDelete,
              ),
      ),
    );
  }
}
