/// One row from `rpc_get_followers` / `rpc_get_following` (migration 0065).
/// Deliberately narrower than [Profile]: only the fields those safe,
/// SECURITY DEFINER RPCs actually return.
final class ProfileConnection {
  const ProfileConnection({
    required this.id,
    required this.fullName,
    this.studentCode,
    this.avatarUrl,
    this.examTargets = const [],
    required this.isFollowing,
  });

  final String id;
  final String fullName;
  final String? studentCode;
  final String? avatarUrl;

  /// `profiles.exam_targets` — a list; the RPC never collapses it to a
  /// single value, so the UI decides how to summarize it (first entry, or
  /// join them) rather than the server guessing which one is "the" target.
  final List<String> examTargets;

  /// Whether the CALLING user (not this row's own user) already follows
  /// this person — drives the Follow / Following / Follow Back button.
  final bool isFollowing;

  String get displayName => fullName.isNotEmpty ? fullName : (studentCode ?? 'Student');

  factory ProfileConnection.fromJson(Map<String, dynamic> json) {
    return ProfileConnection(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?) ?? '',
      studentCode: json['student_code'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      examTargets: (json['exam_targets'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isFollowing: json['is_following'] as bool? ?? false,
    );
  }

  ProfileConnection copyWith({bool? isFollowing}) => ProfileConnection(
        id: id,
        fullName: fullName,
        studentCode: studentCode,
        avatarUrl: avatarUrl,
        examTargets: examTargets,
        isFollowing: isFollowing ?? this.isFollowing,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileConnection && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
