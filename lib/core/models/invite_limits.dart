/// `groups.invite_code` plus its optional expiry/max-uses (migration 0111).
/// Read only through the same GROUP_SETTINGS/owner-gated flow as the code
/// itself — never bundled into the plain group read.
final class InviteLimits {
  const InviteLimits({
    required this.code,
    required this.expiresAt,
    required this.maxUses,
    required this.useCount,
  });

  final String code;

  /// Null means no expiry.
  final DateTime? expiresAt;

  /// Null means unlimited uses.
  final int? maxUses;

  /// How many times this code has been redeemed (join or join-request)
  /// since it was last rotated.
  final int useCount;

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExhausted => maxUses != null && useCount >= maxUses!;

  factory InviteLimits.fromJson(Map<String, dynamic> json) => InviteLimits(
    code: json['invite_code'] as String,
    expiresAt: json['invite_expires_at'] == null
        ? null
        : DateTime.parse(json['invite_expires_at'] as String).toLocal(),
    maxUses: (json['invite_max_uses'] as num?)?.toInt(),
    useCount: (json['invite_use_count'] as num?)?.toInt() ?? 0,
  );
}
