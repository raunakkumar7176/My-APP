/// Canonical content block types supported by the Study System.
enum ContentBlockType {
  heading,
  paragraph,
  definition,
  formula,
  example,
  importantPoint,
  note,
  table,
  image,
  commonMistake,
  unknown;

  static ContentBlockType fromDb(String? value) {
    switch (value) {
      case 'heading':
        return ContentBlockType.heading;
      case 'paragraph':
        return ContentBlockType.paragraph;
      case 'definition':
        return ContentBlockType.definition;
      case 'formula':
        return ContentBlockType.formula;
      case 'example':
        return ContentBlockType.example;
      case 'important_point':
        return ContentBlockType.importantPoint;
      case 'note':
        return ContentBlockType.note;
      case 'table':
        return ContentBlockType.table;
      case 'image':
        return ContentBlockType.image;
      case 'common_mistake':
        return ContentBlockType.commonMistake;
      default:
        return ContentBlockType.unknown;
    }
  }

  String toDb() {
    switch (this) {
      case ContentBlockType.heading:
        return 'heading';
      case ContentBlockType.paragraph:
        return 'paragraph';
      case ContentBlockType.definition:
        return 'definition';
      case ContentBlockType.formula:
        return 'formula';
      case ContentBlockType.example:
        return 'example';
      case ContentBlockType.importantPoint:
        return 'important_point';
      case ContentBlockType.note:
        return 'note';
      case ContentBlockType.table:
        return 'table';
      case ContentBlockType.image:
        return 'image';
      case ContentBlockType.commonMistake:
        return 'common_mistake';
      case ContentBlockType.unknown:
        return 'note';
    }
  }
}

/// Domain model representing a modular learning block within a topic.
final class ContentBlock {
  const ContentBlock({
    required this.id,
    required this.topicId,
    required this.blockType,
    this.orderIndex = 0,
    this.content = const {},
  });

  final String id;
  final String topicId;
  final ContentBlockType blockType;
  final int orderIndex;
  final Map<String, dynamic> content;

  // Convenience helper accessors
  String get text =>
      (content['text'] as String?) ??
      (content['content'] as String?) ??
      (content['title'] as String?) ??
      '';
  String? get latex => content['latex'] as String?;
  List<String> get points {
    final raw = content['points'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }

  String? get mediaUrl =>
      (content['media_url'] as String?) ?? (content['image_url'] as String?);

  factory ContentBlock.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> contentMap = const {};
    if (map['content'] is Map<String, dynamic>) {
      contentMap = map['content'] as Map<String, dynamic>;
    } else if (map['content'] is Map) {
      contentMap = Map<String, dynamic>.from(map['content'] as Map);
    }

    return ContentBlock(
      id: map['id'] as String,
      topicId: map['topic_id'] as String,
      blockType: ContentBlockType.fromDb(map['block_type'] as String?),
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      content: contentMap,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'topic_id': topicId,
      'block_type': blockType.toDb(),
      'order_index': orderIndex,
      'content': content,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentBlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          topicId == other.topicId &&
          orderIndex == other.orderIndex;

  @override
  int get hashCode => Object.hash(id, topicId, orderIndex);
}
