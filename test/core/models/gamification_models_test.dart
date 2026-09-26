// Serialization round-trips for the new gamification/verification/social
// Profile fields, plus PointTransaction and VerificationRequest — matching
// the live column names from 0058_gamification_verification_social_v1.sql
// exactly (app_role, is_vip, verified_badge, verified_expires_at,
// date_of_birth, social_links, followers_count, following_count).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/point_transaction.dart';
import 'package:my_praperation/core/models/profile.dart';
import 'package:my_praperation/core/models/verification_request.dart';

void main() {
  group('Profile — gamification/social fields', () {
    test('fromJson reads every new column with the live snake_case keys', () {
      final json = {
        'id': 'u1',
        'full_name': 'Aisha',
        'timezone': 'Asia/Kolkata',
        'created_at': '2026-01-01T00:00:00Z',
        'bio': '',
        'mobile': '',
        'exam_targets': <String>[],
        'total_points': 1200,
        'weekly_points': 80,
        'app_role': 'scholar',
        'is_vip': true,
        'verified_badge': true,
        'verified_expires_at': '2026-06-01T00:00:00Z',
        'date_of_birth': '2005-03-15',
        'social_links': {'twitter': 'https://x.com/aisha'},
        'followers_count': 42,
        'following_count': 7,
      };
      final p = Profile.fromJson(json);
      expect(p.appRole, AppRole.scholar);
      expect(p.isVip, isTrue);
      expect(p.verifiedBadge, isTrue);
      expect(p.verifiedExpiresAt, DateTime.parse('2026-06-01T00:00:00Z'));
      expect(p.dateOfBirth, DateTime.parse('2005-03-15'));
      expect(p.socialLinks, {'twitter': 'https://x.com/aisha'});
      expect(p.followersCount, 42);
      expect(p.followingCount, 7);
    });

    test('missing new columns default safely (aspirant, not VIP, no badge, empty links, zero counts)', () {
      final json = {
        'id': 'u1',
        'full_name': 'Aisha',
        'timezone': 'Asia/Kolkata',
        'created_at': '2026-01-01T00:00:00Z',
        'bio': '',
        'mobile': '',
        'exam_targets': <String>[],
      };
      final p = Profile.fromJson(json);
      expect(p.appRole, AppRole.aspirant);
      expect(p.isVip, isFalse);
      expect(p.verifiedBadge, isFalse);
      expect(p.verifiedExpiresAt, isNull);
      expect(p.dateOfBirth, isNull);
      expect(p.socialLinks, isEmpty);
      expect(p.followersCount, 0);
      expect(p.followingCount, 0);
    });

    test('toUpdateJson never includes server-controlled privilege/points/counter columns', () {
      final p = Profile.fromJson({
        'id': 'u1',
        'full_name': 'Aisha',
        'timezone': 'Asia/Kolkata',
        'created_at': '2026-01-01T00:00:00Z',
        'bio': '',
        'mobile': '',
        'exam_targets': <String>[],
        'app_role': 'owner',
        'is_vip': true,
        'total_points': 999999,
        'followers_count': 999,
      });
      final update = p.toUpdateJson();
      expect(update.containsKey('app_role'), isFalse);
      expect(update.containsKey('is_vip'), isFalse);
      expect(update.containsKey('verified_badge'), isFalse);
      expect(update.containsKey('verified_expires_at'), isFalse);
      expect(update.containsKey('total_points'), isFalse);
      expect(update.containsKey('weekly_points'), isFalse);
      expect(update.containsKey('followers_count'), isFalse);
      expect(update.containsKey('following_count'), isFalse);
    });

    test('AppRole round-trips through the exact live db strings', () {
      for (final role in AppRole.values) {
        expect(AppRole.fromDb(role.db), role);
      }
      expect(AppRole.fromDb('owner').db, 'owner');
      expect(AppRole.fromDb('core_team').db, 'core_team');
      expect(AppRole.fromDb(null), AppRole.aspirant);
      expect(AppRole.fromDb('something_unknown'), AppRole.aspirant);
    });
  });

  group('PointTransaction', () {
    test('fromJson/toJson round-trip', () {
      final json = {
        'id': 't1',
        'user_id': 'u1',
        'points': 20,
        'reason': 'test_completed',
        'created_at': '2026-01-01T09:00:00Z',
      };
      final t = PointTransaction.fromJson(json);
      expect(t.points, 20);
      expect(t.reason, 'test_completed');
      expect(PointTransaction.fromJson(t.toJson()), t);
    });
  });

  group('VerificationRequest', () {
    test('fromJson maps every live status value', () {
      for (final s in VerificationStatus.values) {
        final json = {
          'id': 'r1',
          'user_id': 'u1',
          'current_points': 1200,
          'status': s.db,
          'created_at': '2026-01-01T00:00:00Z',
        };
        expect(VerificationRequest.fromJson(json).status, s);
      }
    });

    test('isPending/isApproved/isRejected reflect the status exactly', () {
      final pending = VerificationRequest.fromJson({
        'id': 'r1', 'user_id': 'u1', 'current_points': 1200,
        'status': 'pending', 'created_at': '2026-01-01T00:00:00Z',
      });
      expect(pending.isPending, isTrue);
      expect(pending.isApproved, isFalse);
      expect(pending.isRejected, isFalse);
    });

    test('an unknown status string defaults to pending, never crashes', () {
      final json = {
        'id': 'r1', 'user_id': 'u1', 'current_points': null,
        'status': 'something_new', 'created_at': '2026-01-01T00:00:00Z',
      };
      expect(VerificationRequest.fromJson(json).status, VerificationStatus.pending);
    });
  });
}
