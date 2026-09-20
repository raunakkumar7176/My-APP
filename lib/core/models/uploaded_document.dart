/// Represents an uploaded document file for test creation.
///
/// Tracks the file metadata, storage location, and processing state.
final class UploadedDocument {
  const UploadedDocument({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.mimeType,
    required this.fileSize,
    required this.storagePath,
    required this.uploadedBy,
    this.groupId,
    this.status = DocumentStatus.uploaded,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String filePath;
  final String mimeType;
  final int fileSize;
  final String storagePath;
  final String uploadedBy;
  final String? groupId;
  final DocumentStatus status;
  final DateTime? createdAt;

  UploadedDocument copyWith({
    String? id,
    String? fileName,
    String? filePath,
    String? mimeType,
    int? fileSize,
    String? storagePath,
    String? uploadedBy,
    String? groupId,
    DocumentStatus? status,
    DateTime? createdAt,
  }) {
    return UploadedDocument(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      storagePath: storagePath ?? this.storagePath,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      groupId: groupId ?? this.groupId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory UploadedDocument.fromJson(Map<String, dynamic> json) {
    return UploadedDocument(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      filePath: json['file_path'] as String? ?? '',
      mimeType: json['mime_type'] as String,
      fileSize: (json['file_size'] as num).toInt(),
      storagePath: json['storage_path'] as String,
      uploadedBy: json['uploaded_by'] as String,
      groupId: json['group_id'] as String?,
      status: _parseStatus(json['status'] as String?),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'file_path': filePath,
      'mime_type': mimeType,
      'file_size': fileSize,
      'storage_path': storagePath,
      'uploaded_by': uploadedBy,
      'group_id': groupId,
      'status': status.name,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  static DocumentStatus _parseStatus(String? value) {
    switch (value) {
      case 'uploaded':
        return DocumentStatus.uploaded;
      case 'parsing':
        return DocumentStatus.parsing;
      case 'parsed':
        return DocumentStatus.parsed;
      case 'failed':
        return DocumentStatus.failed;
      default:
        return DocumentStatus.uploaded;
    }
  }
}

enum DocumentStatus {
  uploaded,
  parsing,
  parsed,
  failed,
}
