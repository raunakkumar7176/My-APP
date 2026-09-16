import 'package:supabase_flutter/supabase_flutter.dart';

final class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    required this.timezone,
    required this.createdAt,
    this.studentCode,
    required this.bio,
    required this.mobile,
    required this.examTargets,
  });

  final String id;
  final String fullName;
  final String? avatarUrl;
  final String timezone;
  final DateTime createdAt;
  final String? studentCode;
  final String bio;
  final String mobile;
  final List<String> examTargets;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      timezone: (json['timezone'] as String?) ?? 'Asia/Kolkata',
      createdAt: DateTime.parse(json['created_at'] as String),
      studentCode: json['student_code'] as String?,
      bio: (json['bio'] as String?) ?? '',
      mobile: (json['mobile'] as String?) ?? '',
      examTargets: (json['exam_targets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'timezone': timezone,
      'created_at': createdAt.toIso8601String(),
      'student_code': studentCode,
      'bio': bio,
      'mobile': mobile,
      'exam_targets': examTargets,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'full_name': fullName,
      'bio': bio,
      'mobile': mobile,
      'timezone': timezone,
      'exam_targets': examTargets,
    };
  }

  Profile copyWith({
    String? fullName,
    String? avatarUrl,
    String? timezone,
    String? studentCode,
    String? bio,
    String? mobile,
    List<String>? examTargets,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt,
      studentCode: studentCode ?? this.studentCode,
      bio: bio ?? this.bio,
      mobile: mobile ?? this.mobile,
      examTargets: examTargets ?? this.examTargets,
    );
  }

  String get displayName =>
      fullName.isNotEmpty ? fullName : (studentCode ?? 'Student');

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fullName == other.fullName &&
          avatarUrl == other.avatarUrl &&
          timezone == other.timezone &&
          createdAt == other.createdAt &&
          studentCode == other.studentCode &&
          bio == other.bio &&
          mobile == other.mobile &&
          _listEquals(examTargets, other.examTargets);

  @override
  int get hashCode => Object.hash(
        id,
        fullName,
        avatarUrl,
        timezone,
        createdAt,
        studentCode,
        bio,
        mobile,
        Object.hashAll(examTargets),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Profile fromUser(User user) {
    final metadata = user.userMetadata ?? {};
    return Profile(
      id: user.id,
      fullName: (metadata['full_name'] as String?) ??
          (metadata['name'] as String?) ??
          '',
      avatarUrl: metadata['avatar_url'] as String?,
      timezone: 'Asia/Kolkata',
      createdAt: DateTime.parse(user.createdAt),
      studentCode: null,
      bio: '',
      mobile: '',
      examTargets: const [],
    );
  }
}
