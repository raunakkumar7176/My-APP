import '../models/profile.dart';

/// Central VIP/entitlement check — the single place that decides whether a
/// user is exempt from ads/paywalls. `owner` and `core_team` are always VIP
/// by role; anyone else is VIP only while `profiles.is_vip` is true (set by
/// `rpc_approve_blue_tick` alongside `verified_badge`, and cleared by
/// `rpc_check_and_revoke_badges` once `verified_expires_at` passes). This
/// mirrors the server's own privilege model — it never invents a client-only
/// notion of VIP that the database doesn't also enforce.
abstract final class EntitlementService {
  static bool isVipUser(Profile profile) =>
      profile.appRole == AppRole.owner ||
      profile.appRole == AppRole.coreTeam ||
      profile.isVip;

  /// True once a `verified_expires_at` in the past should be treated as
  /// expired locally, even before the server's revocation sweep runs.
  static bool isVerificationExpired(Profile profile) {
    final expires = profile.verifiedExpiresAt;
    if (expires == null) return false;
    return DateTime.now().toUtc().isAfter(expires.toUtc());
  }

  /// A profile only counts as verified-and-current when the badge is set
  /// AND it hasn't already passed its expiry.
  static bool isVerified(Profile profile) =>
      profile.verifiedBadge && !isVerificationExpired(profile);

  /// Whether an ad wrapper around [child] should be bypassed for [profile].
  /// Callers pass their normal ad widget as [child] and their VIP-only
  /// content as [vipChild]; this only decides which one applies.
  static T resolveAdGate<T>({
    required Profile profile,
    required T withAds,
    required T vipChild,
  }) =>
      isVipUser(profile) ? vipChild : withAds;

  /// Whether a paywalled feature should be unlocked for [profile] without
  /// going through the normal purchase/subscription flow.
  static bool bypassesPaywall(Profile profile) => isVipUser(profile);
}
