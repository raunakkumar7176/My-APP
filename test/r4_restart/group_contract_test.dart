// Group model = exact live rpc_get_user_groups() row (R4 D).
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/group.dart';

void main() {
  test('parses the 7-column RPC row; no created_by / updated_at', () {
    final g = Group.fromJson({
      'id': 'g-1',
      'name': 'Batch A',
      'owner_id': 'u-owner',
      'logo_url': null,
      'created_at': '2026-09-17T05:00:00+00:00',
      'member_count': 3,
      'user_role': 'leader',
    });
    expect(g.ownerId, 'u-owner');
    expect(g.logoUrl, isNull);
    expect(g.memberCount, 3);
    expect(g.isLeader, isTrue);
    expect(g.toJson().keys, [
      'id',
      'name',
      'owner_id',
      'logo_url',
      'created_at',
      'member_count',
      'user_role',
    ]);
    expect(g.toJson().containsKey('invite_code'), isFalse);
  });

  test('owner without a membership row is reported as owner; default role is member', () {
    final owner = Group.fromJson({
      'id': 'g',
      'name': 'G',
      'owner_id': 'me',
      'created_at': '2026-09-17T05:00:00Z',
      'member_count': 0,
      'user_role': 'owner',
    });
    expect(owner.isOwner, isTrue);
    final plain = Group.fromJson({
      'id': 'g',
      'name': 'G',
      'owner_id': 'x',
      'created_at': '2026-09-17T05:00:00Z',
    });
    expect(plain.userRole, 'member');
    expect(plain.memberCount, 0);
  });
}
