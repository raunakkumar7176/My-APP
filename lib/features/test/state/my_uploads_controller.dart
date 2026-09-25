import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/document_service.dart';
import 'disposable_notifier.dart';

enum MyUploadsLoadState { idle, loading, loaded, error }

/// Lists the current user's own uploaded documents (Storage + metadata),
/// and lets them delete individual files or clean up any orphaned Storage
/// objects a partial failure may have left behind. Separate from
/// [DocumentUploadController], which only ever tracks the single in-flight
/// upload of the create-test wizard — this one is a standing library view.
class MyUploadsController extends DisposableNotifier {
  MyUploadsController({DocumentService? documentService})
    : _docService = documentService ?? SupabaseDocumentService();

  final DocumentService _docService;

  MyUploadsLoadState _state = MyUploadsLoadState.idle;
  String? _errorMessage;
  List<UploadedDocumentRecord> _documents = [];
  final Set<String> _deletingIds = {};
  bool _cleaningUp = false;
  int? _lastCleanupCount;

  MyUploadsLoadState get state => _state;
  String? get errorMessage => _errorMessage;
  List<UploadedDocumentRecord> get documents => List.unmodifiable(_documents);
  bool isDeleting(String id) => _deletingIds.contains(id);
  bool get isCleaningUp => _cleaningUp;
  int? get lastCleanupCount => _lastCleanupCount;

  Future<void> load() async {
    _state = MyUploadsLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _documents = await _docService.listMyDocuments();
      _state = MyUploadsLoadState.loaded;
    } on AppError catch (e) {
      _errorMessage = e.message;
      _state = MyUploadsLoadState.error;
    } catch (e, st) {
      AppLogger.error('listMyDocuments failed: $e', stackTrace: st);
      _errorMessage = 'Failed to load your uploaded files.';
      _state = MyUploadsLoadState.error;
    }
    notifyListeners();
  }

  /// Deletes one document (Storage object, then metadata row) and removes
  /// it from the in-memory list on success — no full reload needed.
  Future<String?> delete(UploadedDocumentRecord doc) async {
    _deletingIds.add(doc.id);
    notifyListeners();

    String? error;
    try {
      await _docService.deleteDocument(doc);
      _documents = _documents.where((d) => d.id != doc.id).toList();
    } on AppError catch (e) {
      error = e.message;
    } catch (e, st) {
      AppLogger.error('deleteDocument failed: $e', stackTrace: st);
      error = 'Failed to delete the file. Please try again.';
    }

    _deletingIds.remove(doc.id);
    notifyListeners();
    return error;
  }

  /// Removes Storage objects with no matching metadata row (e.g. left
  /// behind by a partial failure before this session's compensating
  /// cleanup was added, or a row deleted directly). Returns an error
  /// message on failure, null on success.
  Future<String?> cleanupOrphans() async {
    _cleaningUp = true;
    notifyListeners();

    String? error;
    try {
      _lastCleanupCount = await _docService.cleanupOrphanedStorage();
    } on AppError catch (e) {
      error = e.message;
    } catch (e, st) {
      AppLogger.error('cleanupOrphanedStorage failed: $e', stackTrace: st);
      error = 'Failed to clean up orphaned files.';
    }

    _cleaningUp = false;
    notifyListeners();
    return error;
  }
}
