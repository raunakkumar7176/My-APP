/// One row of `rpc_find_profile_by_student_code` — the minimum identity an
/// invitation UI needs: `id, full_name, avatar_url, student_code`. Nothing
/// else is ever returned by the function, and nothing else is modelled.
final class ProfileMatch {
  const ProfileMatch({
    required this.id,
    required this.fullName,
    required this.studentCode,
    this.avatarUrl,
  });

  final String id;
  final String fullName;
  final String studentCode;
  final String? avatarUrl;

  String get displayName => fullName.trim().isEmpty ? 'Student' : fullName.trim();

  factory ProfileMatch.fromJson(Map<String, dynamic> json) {
    return ProfileMatch(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?) ?? '',
      studentCode: (json['student_code'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'student_code': studentCode,
    'avatar_url': avatarUrl,
  };
}
