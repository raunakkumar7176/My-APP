enum MaterialStatus { uploaded, processing, ready, failed, unknown }

MaterialStatus _parseMaterialStatus(String? value) {
  switch (value) {
    case 'uploaded':
      return MaterialStatus.uploaded;
    case 'processing':
      return MaterialStatus.processing;
    case 'ready':
      return MaterialStatus.ready;
    case 'failed':
      return MaterialStatus.failed;
    default:
      return MaterialStatus.unknown;
  }
}

final class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.groupId,
    required this.uploadedBy,
    required this.title,
    required this.storagePath,
    required this.mimeType,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String uploadedBy;
  final String title;
  final String storagePath;
  final String mimeType;
  final MaterialStatus status;
  final DateTime createdAt;

  bool get isReady => status == MaterialStatus.ready;
  bool get isPdf => mimeType == 'application/pdf';

  factory StudyMaterial.fromJson(Map<String, dynamic> json) {
    return StudyMaterial(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      uploadedBy: json['uploaded_by'] as String,
      title: json['title'] as String,
      storagePath: json['storage_path'] as String,
      mimeType: (json['mime_type'] as String?) ?? 'application/pdf',
      status: _parseMaterialStatus(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'uploaded_by': uploadedBy,
      'title': title,
      'storage_path': storagePath,
      'mime_type': mimeType,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudyMaterial &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          groupId == other.groupId &&
          uploadedBy == other.uploadedBy &&
          title == other.title &&
          storagePath == other.storagePath &&
          mimeType == other.mimeType &&
          status == other.status &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        uploadedBy,
        title,
        storagePath,
        mimeType,
        status,
        createdAt,
      );
}
