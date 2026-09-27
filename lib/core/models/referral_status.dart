/// Result of `rpc_claim_referral_reward` (migration 0066).
final class ReferralApplyResult {
  const ReferralApplyResult({
    required this.success,
    this.error,
    this.pointsAwarded,
    this.referrerName,
  });

  final bool success;

  /// 'INVALID_REFERRAL_CODE' | 'CANNOT_REFER_SELF' | 'ALREADY_REFERRED', or
  /// null on success.
  final String? error;

  /// Points awarded to the CALLING (joining) user — 100 per spec.
  final int? pointsAwarded;

  /// The referrer's display name, for the celebratory message.
  final String? referrerName;

  String get friendlyError {
    switch (error) {
      case 'INVALID_REFERRAL_CODE':
        return 'That referral code doesn\'t exist. Double-check it and try again.';
      case 'CANNOT_REFER_SELF':
        return 'You can\'t use your own referral code.';
      case 'ALREADY_REFERRED':
        return 'A referral code has already been applied to your account.';
      default:
        return 'Could not apply the referral code. Please try again.';
    }
  }

  factory ReferralApplyResult.fromJson(Map<String, dynamic> json) {
    return ReferralApplyResult(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
      pointsAwarded: (json['points_awarded'] as num?)?.toInt(),
      referrerName: json['referrer_name'] as String?,
    );
  }
}

/// The caller's own referral summary, from `rpc_get_my_referral_status`.
final class ReferralStatus {
  const ReferralStatus({
    required this.hasBeenReferred,
    required this.referralCount,
    required this.pointsEarned,
  });

  final bool hasBeenReferred;
  final int referralCount;
  final int pointsEarned;

  factory ReferralStatus.fromJson(Map<String, dynamic> json) {
    return ReferralStatus(
      hasBeenReferred: json['has_been_referred'] as bool? ?? false,
      referralCount: (json['referral_count'] as num?)?.toInt() ?? 0,
      pointsEarned: (json['points_earned_from_referrals'] as num?)?.toInt() ?? 0,
    );
  }
}
