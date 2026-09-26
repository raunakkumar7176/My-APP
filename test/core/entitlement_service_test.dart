// EntitlementService: the single VIP/ad/paywall-bypass gate, mirroring the
// server's own privilege model (owner/core_team always VIP by role;
// everyone else only while is_vip is true, per 0058's rpc_approve_blue_tick
// / rpc_check_and_revoke_badges).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/profile.dart';
import 'package:my_praperation/core/services/entitlement_service.dart';

Profile _profile({
  AppRole appRole = AppRole.aspirant,
  bool isVip = false,
  bool verifiedBadge = false,
  DateTime? verifiedExpiresAt,
}) => Profile(
  id: 'u1',
  fullName: 'Test',
  timezone: 'Asia/Kolkata',
  createdAt: DateTime(2026, 1, 1),
  bio: '',
  mobile: '',
  examTargets: const [],
  appRole: appRole,
  isVip: isVip,
  verifiedBadge: verifiedBadge,
  verifiedExpiresAt: verifiedExpiresAt,
);

void main() {
  group('isVipUser', () {
    test('owner is always VIP, even with is_vip false', () {
      expect(EntitlementService.isVipUser(_profile(appRole: AppRole.owner)), isTrue);
    });

    test('core_team is always VIP, even with is_vip false', () {
      expect(EntitlementService.isVipUser(_profile(appRole: AppRole.coreTeam)), isTrue);
    });

    test('a plain aspirant with is_vip false is not VIP', () {
      expect(EntitlementService.isVipUser(_profile()), isFalse);
    });

    test('a scholar with is_vip true (approved blue tick) is VIP', () {
      expect(EntitlementService.isVipUser(_profile(appRole: AppRole.scholar, isVip: true)), isTrue);
    });
  });

  group('verification expiry', () {
    test('no expiry set is never treated as expired', () {
      expect(EntitlementService.isVerificationExpired(_profile()), isFalse);
    });

    test('a future expiry is not expired', () {
      final future = DateTime.now().add(const Duration(days: 30));
      expect(EntitlementService.isVerificationExpired(_profile(verifiedExpiresAt: future)), isFalse);
    });

    test('a past expiry is expired', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(EntitlementService.isVerificationExpired(_profile(verifiedExpiresAt: past)), isTrue);
    });

    test('isVerified is false once expired, even if verifiedBadge is still true locally', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final p = _profile(verifiedBadge: true, verifiedExpiresAt: past);
      expect(EntitlementService.isVerified(p), isFalse);
    });

    test('isVerified is true when badge is set and not expired', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final p = _profile(verifiedBadge: true, verifiedExpiresAt: future);
      expect(EntitlementService.isVerified(p), isTrue);
    });
  });

  group('resolveAdGate / bypassesPaywall', () {
    test('a VIP resolves to the vip child, a non-VIP resolves to the ad-bearing one', () {
      final vip = _profile(appRole: AppRole.owner);
      final regular = _profile();
      expect(
        EntitlementService.resolveAdGate(profile: vip, withAds: 'ads', vipChild: 'no-ads'),
        'no-ads',
      );
      expect(
        EntitlementService.resolveAdGate(profile: regular, withAds: 'ads', vipChild: 'no-ads'),
        'ads',
      );
    });

    test('bypassesPaywall mirrors isVipUser exactly', () {
      final vip = _profile(isVip: true);
      final regular = _profile();
      expect(EntitlementService.bypassesPaywall(vip), isTrue);
      expect(EntitlementService.bypassesPaywall(regular), isFalse);
    });
  });
}
