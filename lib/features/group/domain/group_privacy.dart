/// The live `groups.privacy` CHECK: public | private | restricted.
///
/// Join behaviour is the server's (`fn_join_group`): `restricted` files a row
/// in `group_join_requests` and returns NULL instead of a group id; the other
/// two join immediately. The descriptions below only explain that to the user.
enum GroupPrivacy {
  public,
  private,
  restricted;

  static GroupPrivacy fromDb(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'private':
        return GroupPrivacy.private;
      case 'restricted':
        return GroupPrivacy.restricted;
      default:
        return GroupPrivacy.public;
    }
  }

  String get db => name;

  String get label {
    switch (this) {
      case GroupPrivacy.public:
        return 'Public';
      case GroupPrivacy.private:
        return 'Private';
      case GroupPrivacy.restricted:
        return 'Restricted';
    }
  }

  String get description {
    switch (this) {
      case GroupPrivacy.public:
        return 'Anyone signed in can find this group. Joining with the invite code is instant.';
      case GroupPrivacy.private:
        return 'Only people with the invite code can find and join this group.';
      case GroupPrivacy.restricted:
        return 'The invite code sends a join request that a group manager must approve.';
    }
  }

  /// True when `fn_join_group` files a request instead of adding a member.
  bool get requiresApproval => this == GroupPrivacy.restricted;
}
