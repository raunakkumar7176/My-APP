final class MaterialChunk {
  const MaterialChunk({
    required this.id,
    required this.materialId,
    required this.idx,
    required this.content,
  });

  final String id;
  final String materialId;
  final int idx;
  final String content;

  factory MaterialChunk.fromJson(Map<String, dynamic> json) {
    return MaterialChunk(
      id: json['id'] as String,
      materialId: json['material_id'] as String,
      idx: json['idx'] as int,
      content: json['content'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'material_id': materialId,
      'idx': idx,
      'content': content,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaterialChunk &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          materialId == other.materialId &&
          idx == other.idx &&
          content == other.content;

  @override
  int get hashCode => Object.hash(id, materialId, idx, content);
}
