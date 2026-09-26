import 'package:supabase_flutter/supabase_flutter.dart';

/// Live `app_role` enum values (`profiles_app_role_check` in
/// `0058_gamification_verification_social_v1.sql`). Ordered highest to
/// lowest privilege; `aspirant` is the default for every new signup.
enum AppRole {
  owner,
  coreTeam,
  scholar,
  aspirant;

  static AppRole fromDb(String? value) {
    switch (value) {
      case 'owner':
        return AppRole.owner;
      case 'core_team':
        return AppRole.coreTeam;
      case 'scholar':
        return AppRole.scholar;
      case 'aspirant':
      default:
        return AppRole.aspirant;
    }
  }

  String get db {
    switch (this) {
      case AppRole.owner:
        return 'owner';
      case AppRole.coreTeam:
        return 'core_team';
      case AppRole.scholar:
        return 'scholar';
      case AppRole.aspirant:
        return 'aspirant';
    }
  }
}

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
    this.totalPoints = 0,
    this.weeklyPoints = 0,
    this.appRole = AppRole.aspirant,
    this.isVip = false,
    this.verifiedBadge = false,
    this.verifiedExpiresAt,
    this.dateOfBirth,
    this.socialLinks = const {},
    this.followersCount = 0,
    this.followingCount = 0,
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
  final int totalPoints;

  /// Historically a stored `profiles.weekly_points` column; migration 0059
  /// drops that column and computes weekly points only via
  /// `rpc_get_weekly_cohort_leaderboard`/`rpc_search_student_by_code`. Kept
  /// here for backward compatibility with existing callers, but a plain
  /// `.from('profiles').select(...)` will no longer populate it once 0059
  /// is live — only the leaderboard/search RPCs can.
  final int weeklyPoints;

  /// `profiles.app_role` — 'owner' | 'core_team' | 'scholar' | 'aspirant'.
  final AppRole appRole;

  /// `profiles.is_vip` — true for the owner/core team or an approved
  /// blue-tick holder (`rpc_approve_blue_tick` sets both `is_vip` and
  /// `verified_badge` together).
  final bool isVip;

  /// `profiles.verified_badge` — the blue-tick indicator itself.
  final bool verifiedBadge;

  /// `profiles.verified_expires_at` — null means never verified, or the
  /// badge has no expiry set. A non-null value in the past means the badge
  /// should be treated as expired even if `verifiedBadge` hasn't been
  /// server-revoked yet (`rpc_check_and_revoke_badges` does that sweep).
  final DateTime? verifiedExpiresAt;

  /// `profiles.date_of_birth`.
  final DateTime? dateOfBirth;

  /// `profiles.social_links` — a flat `{platform: url}` jsonb object.
  final Map<String, String> socialLinks;

  /// `profiles.followers_count` / `following_count` — denormalised
  /// counters maintained server-side by `fn_sync_follow_counts` on
  /// `user_follows` inserts/deletes. Never write these directly.
  final int followersCount;
  final int followingCount;

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
      totalPoints: (json['total_points'] as num?)?.toInt() ?? 0,
      weeklyPoints: (json['weekly_points'] as num?)?.toInt() ?? 0,
      appRole: AppRole.fromDb(json['app_role'] as String?),
      isVip: json['is_vip'] as bool? ?? false,
      verifiedBadge: json['verified_badge'] as bool? ?? false,
      verifiedExpiresAt: json['verified_expires_at'] == null
          ? null
          : DateTime.parse(json['verified_expires_at'] as String),
      dateOfBirth: json['date_of_birth'] == null
          ? null
          : DateTime.parse(json['date_of_birth'] as String),
      socialLinks: (json['social_links'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          const {},
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
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
      'total_points': totalPoints,
      'weekly_points': weeklyPoints,
      'app_role': appRole.db,
      'is_vip': isVip,
      'verified_badge': verifiedBadge,
      'verified_expires_at': verifiedExpiresAt?.toIso8601String(),
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'social_links': socialLinks,
      'followers_count': followersCount,
      'following_count': followingCount,
    };
  }

  /// Editable-by-the-user fields only — `app_role`, `is_vip`,
  /// `verified_badge`, `verified_expires_at`, points and follow counters are
  /// server-controlled and must never appear in a client UPDATE payload
  /// (the live `profiles` RLS update policy specifically guards those
  /// privilege columns — see 0058 §1).
  Map<String, dynamic> toUpdateJson() {
    return {
      'full_name': fullName,
      'bio': bio,
      'mobile': mobile,
      'timezone': timezone,
      'exam_targets': examTargets,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'social_links': socialLinks,
    };
  }

  Profile copyWith({
    String? fullName,
    String? avatarUrl,
    // `avatarUrl: null` is ambiguous with "not passed" under the usual
    // `??` pattern (needed to clear a photo back to the default avatar) —
    // this flag disambiguates it.
    bool clearAvatar = false,
    String? timezone,
    String? studentCode,
    String? bio,
    String? mobile,
    List<String>? examTargets,
    int? totalPoints,
    int? weeklyPoints,
    AppRole? appRole,
    bool? isVip,
    bool? verifiedBadge,
    DateTime? verifiedExpiresAt,
    DateTime? dateOfBirth,
    Map<String, String>? socialLinks,
    int? followersCount,
    int? followingCount,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      timezone: timezone ?? this.timezone,
      createdAt: createdAt,
      studentCode: studentCode ?? this.studentCode,
      bio: bio ?? this.bio,
      mobile: mobile ?? this.mobile,
      examTargets: examTargets ?? this.examTargets,
      totalPoints: totalPoints ?? this.totalPoints,
      weeklyPoints: weeklyPoints ?? this.weeklyPoints,
      appRole: appRole ?? this.appRole,
      isVip: isVip ?? this.isVip,
      verifiedBadge: verifiedBadge ?? this.verifiedBadge,
      verifiedExpiresAt: verifiedExpiresAt ?? this.verifiedExpiresAt,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      socialLinks: socialLinks ?? this.socialLinks,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
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
          totalPoints == other.totalPoints &&
          weeklyPoints == other.weeklyPoints &&
          appRole == other.appRole &&
          isVip == other.isVip &&
          verifiedBadge == other.verifiedBadge &&
          verifiedExpiresAt == other.verifiedExpiresAt &&
          dateOfBirth == other.dateOfBirth &&
          followersCount == other.followersCount &&
          followingCount == other.followingCount &&
          _mapEquals(socialLinks, other.socialLinks) &&
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
        totalPoints,
        weeklyPoints,
        appRole,
        isVip,
        verifiedBadge,
        verifiedExpiresAt,
        dateOfBirth,
        followersCount,
        followingCount,
        Object.hashAll(examTargets),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
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
      totalPoints: 0,
      weeklyPoints: 0,
    );
  }
}
