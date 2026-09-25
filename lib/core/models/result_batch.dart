enum BatchStatus {
  pending,
  processing,
  partiallyCompleted,
  completed,
  failed,
  unknown,
}

BatchStatus _parseBatchStatus(String? value) {
  switch (value) {
    case 'pending':
      return BatchStatus.pending;
    case 'processing':
      return BatchStatus.processing;
    case 'partially_completed':
      return BatchStatus.partiallyCompleted;
    case 'completed':
      return BatchStatus.completed;
    case 'failed':
      return BatchStatus.failed;
    default:
      return BatchStatus.unknown;
  }
}

final class ResultBatch {
  const ResultBatch({
    required this.id,
    required this.testId,
    this.requestedBy,
    required this.status,
    this.reportsDone,
    this.reportsTotal,
    this.totals,
    this.createdAt,
    this.completedAt,
    this.errors,
    this.reused = false,
    this.publishedAt,
    this.publishedBy,
  });

  final String id;
  final String testId;
  final String? requestedBy;
  final BatchStatus status;
  final int? reportsDone;
  final int? reportsTotal;
  final Map<String, dynamic>? totals;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// Set only by `rpc_publish_results`. NULL means the batch is scored but
  /// not yet visible to students — "submitted" and "published" are two
  /// separate events by product rule; this is never set by generation alone.
  final DateTime? publishedAt;
  final String? publishedBy;

  /// Number of per-user reports that failed inside the batch (from the RPC).
  /// `errors > 0` does NOT mean the RPC call failed.
  final int? errors;

  /// True when `rpc_generate_results` returned an existing batch instead of
  /// starting a new one (idempotent re-request).
  final bool reused;

  bool get isPending => status == BatchStatus.pending;
  bool get isProcessing => status == BatchStatus.processing;
  bool get isPartiallyCompleted => status == BatchStatus.partiallyCompleted;
  bool get isCompleted => status == BatchStatus.completed;
  bool get isFailed => status == BatchStatus.failed;
  bool get isTerminal => isCompleted || isFailed;
  bool get canTrigger => !isPending && !isProcessing;
  bool get hasErrors => (errors ?? 0) > 0;

  /// True once an authorized user has run `rpc_publish_results` — the only
  /// signal that governs student-visible result access for a group test.
  bool get isPublished => publishedAt != null;

  /// A completed/partially-completed batch that has not yet been published —
  /// i.e. generation finished but the authorized publish action is still
  /// pending. Drives the "Publish Result" affordance for result managers.
  bool get canPublish => (isCompleted || isPartiallyCompleted) && !isPublished;

  double get progress {
    if (reportsTotal == null || reportsTotal == 0) return 0;
    return (reportsDone ?? 0) / reportsTotal!;
  }

  /// Parses the LIVE `rpc_generate_results(p_test_id)` jsonb (verified
  /// 2026-09-16): `{batch_id, test_id, status, reports_done, reports_total,
  /// errors, reused}`. Row-only fields (`requested_by`, `totals`, timestamps)
  /// are not returned by the RPC and stay null — never invented.
  factory ResultBatch.fromRpcJson(Map<String, dynamic> json) {
    return ResultBatch(
      id: json['batch_id'] as String,
      testId: json['test_id'] as String? ?? '',
      status: _parseBatchStatus(json['status'] as String?),
      reportsDone: (json['reports_done'] as num?)?.toInt(),
      reportsTotal: (json['reports_total'] as num?)?.toInt(),
      errors: (json['errors'] as num?)?.toInt(),
      reused: json['reused'] == true,
    );
  }

  /// Parses the (proposed) `rpc_publish_results(p_test_id)` jsonb:
  /// `{batch_id, test_id, status: 'published', published_at, notified, reused}`.
  factory ResultBatch.fromPublishRpcJson(Map<String, dynamic> json) {
    return ResultBatch(
      id: json['batch_id'] as String,
      testId: json['test_id'] as String? ?? '',
      status: BatchStatus.completed,
      reused: json['reused'] == true,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
    );
  }

  /// Parses a `public.result_batches` row.
  factory ResultBatch.fromJson(Map<String, dynamic> json) {
    return ResultBatch(
      id: json['id'] as String,
      testId: json['test_id'] as String,
      requestedBy: json['requested_by'] as String?,
      status: _parseBatchStatus(json['status'] as String?),
      reportsDone: (json['reports_done'] as num?)?.toInt(),
      reportsTotal: (json['reports_total'] as num?)?.toInt(),
      totals: json['totals'] != null
          ? Map<String, dynamic>.from(json['totals'] as Map)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      publishedBy: json['published_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'test_id': testId,
      'requested_by': requestedBy,
      'status': status.name,
      'reports_done': reportsDone,
      'reports_total': reportsTotal,
      'totals': totals,
      'created_at': createdAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
      'published_by': publishedBy,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultBatch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          testId == other.testId &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, testId, status);
}
