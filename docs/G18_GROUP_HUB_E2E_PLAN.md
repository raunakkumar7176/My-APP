# G18 Group Hub End-to-End Test Plan

## 1. G17 Dependency Notice

> **⚠️ IMPORTANT: G18 final security/production acceptance is blocked until G17 security audit is PASS.**
> 
> All test results are provisional until G17 migrations are verified and security audit completes.

## 2. Prerequisites

### Environment Setup
- [ ] Supabase project with G1-G17 migrations applied
- [ ] Test accounts configured (Owner, Leader, Moderator, Member, Non-member)
- [ ] Android device/emulator with debug APK installed
- [ ] Network connectivity to Supabase verified
- [ ] G17 security audit status: ☐ PASS ☐ PENDING

### Database State
- [ ] G1-G17 migrations applied successfully
- [ ] Test data seeded (group, rules, announcements)
- [ ] RLS policies active and verified

## 3. Test Users/Roles

| Account | Email | Role | Expected Permissions |
|---------|-------|------|---------------------|
| Owner | owner@test.com | owner | Full control: create, edit, delete, manage members, manage settings |
| Leader | leader@test.com | leader | Create tests, announcements, manage members, moderate chat |
| Moderator | mod@test.com | moderator | Moderate chat, manage members (limited) |
| Member | member@test.com | member | View content, take tests, chat, leave group |
| Non-member | outsider@test.com | none | Can search groups, join public, request private |

## 4. Required Permissions Matrix

| Action | Owner | Leader | Moderator | Member | Non-member |
|--------|-------|--------|-----------|--------|------------|
| Create group | ✅ | ❌ | ❌ | ❌ | ❌ |
| Edit group settings | ✅ | ❌ | ❌ | ❌ | ❌ |
| Delete group | ✅ | ❌ | ❌ | ❌ | ❌ |
| Add members | ✅ | ✅ | ✅ | ❌ | ❌ |
| Remove members | ✅ | ✅ | ❌ | ❌ | ❌ |
| Change roles | ✅ | ❌ | ❌ | ❌ | ❌ |
| Create tests | ✅ | ✅ | ❌ | ❌ | ❌ |
| Publish tests | ✅ | ✅ | ❌ | ❌ | ❌ |
| Enter tests | ✅ | ✅ | ✅ | ✅ | ❌ |
| View results | ✅ | ✅ | ✅ | ✅ | ❌ |
| View leaderboard | ✅ | ✅ | ✅ | ✅ | ❌ |
| Send chat | ✅ | ✅ | ✅ | ✅ | ❌ |
| Moderate chat | ✅ | ✅ | ✅ | ❌ | ❌ |
| Create announcements | ✅ | ✅ | ❌ | ❌ | ❌ |
| Read announcements | ✅ | ✅ | ✅ | ✅ | ❌ |
| Leave group | ✅ | ✅ | ✅ | ✅ | ❌ |
| Join public group | ❌ | ❌ | ❌ | ❌ | ✅ |
| Request private group | ❌ | ❌ | ❌ | ❌ | ✅ |

## 5. Test Data

### Pre-seeded Group
- **Group ID**: `test-group-001`
- **Group Name**: `Test Study Group`
- **Privacy**: Public
- **Invite Code**: `TEST1234`

### Pre-created Rules
1. "Be respectful to all members"
2. "No spam or off-topic messages"
3. "Use appropriate language"

### Pre-created Announcements
1. "Welcome to the test group!"
2. "Exam schedule posted"

## 6. Execution Order

### Journey A: Group Creation (Owner)
**Actor**: Owner account  
**Steps**:
1. Login as Owner
2. Navigate to Groups
3. Tap "Create Group"
4. Enter group name: "E2E Test Group"
5. Enter description: "Test group for E2E validation"
6. Set privacy: Public
7. Generate invite code
8. Confirm creation

**Expected Results**:
- [ ] Group created successfully
- [ ] Owner role assigned
- [ ] Group appears in "My Groups"
- [ ] Invite code generated
- [ ] Navigation to group detail screen

### Journey B: Member Join (Public Group)
**Actor**: Non-member account  
**Prerequisites**: Public group exists (Journey A or seeded)  
**Steps**:
1. Login as Non-member
2. Search for "Test Study Group"
3. View group details
4. Tap "Join Group"
5. Confirm membership

**Expected Results**:
- [ ] Group found in search
- [ ] Group details displayed
- [ ] Join successful
- [ ] Member role assigned
- [ ] Group added to "My Groups"

### Journey C: Invitation Flow (Manager Invite, Member Accept)
**Actor**: Leader account, then Member account  
**Steps**:
1. Login as Leader
2. Navigate to group members
3. Tap "Invite Member"
4. Enter member email
5. Send invitation
6. Login as Member
7. View notifications
8. Accept invitation

**Expected Results**:
- [ ] Invitation sent successfully
- [ ] Notification received by Member
- [ ] Invitation details correct
- [ ] Acceptance successful
- [ ] Member added to group

### Journey D: Join Request (Restricted Group)
**Actor**: Non-member account  
**Prerequisites**: Restricted group exists  
**Steps**:
1. Login as Non-member
2. Search for restricted group
3. View group details
4. Tap "Request to Join"
5. Add message (optional)
6. Submit request
7. Login as Manager
8. View pending requests
9. Approve request

**Expected Results**:
- [ ] Request submitted successfully
- [ ] Request appears in manager's queue
- [ ] Manager can view request details
- [ ] Approval successful
- [ ] Member added to group

### Journey E: Role Management (Owner Promote)
**Actor**: Owner account  
**Steps**:
1. Login as Owner
2. Navigate to group members
3. Select Member account
4. Tap "Change Role"
5. Select "Leader"
6. Confirm change

**Expected Results**:
- [ ] Role change interface accessible
- [ ] Role options available
- [ ] Change successful
- [ ] Permissions updated immediately
- [ ] Member can now create tests/announcements

### Journey F: Settings (Owner Edit)
**Actor**: Owner account  
**Steps**:
1. Login as Owner
2. Navigate to group settings
3. Edit group name: "Updated Test Group"
4. Edit description: "Updated description"
5. Change privacy: Private
6. Save changes

**Expected Results**:
- [ ] Settings interface accessible
- [ ] Fields editable
- [ ] Changes saved successfully
- [ ] Updates reflected immediately
- [ ] Other members see changes

### Journey G: Chat (Member Send/Receive)
**Actor**: Member account  
**Steps**:
1. Login as Member
2. Navigate to group chat
3. Send message: "Hello from E2E test!"
4. Verify message appears
5. Scroll up to load history
6. Verify pagination works

**Expected Results**:
- [ ] Chat interface accessible
- [ ] Message sent successfully
- [ ] Message appears in chat
- [ ] Timestamp correct
- [ ] Pagination loads older messages
- [ ] No performance issues

### Journey H: Announcements (Leader Post, Member Read)
**Actor**: Leader account, then Member account  
**Steps**:
1. Login as Leader
2. Navigate to group announcements
3. Tap "Create Announcement"
4. Enter title: "E2E Test Announcement"
5. Enter content: "This is a test announcement"
6. Publish announcement
7. Login as Member
8. View announcements
9. Verify announcement visible

**Expected Results**:
- [ ] Announcement creation accessible
- [ ] Form validates correctly
- [ ] Announcement published successfully
- [ ] Member can view announcement
- [ ] Announcement appears in list
- [ ] Content displays correctly

### Journey I: Tests (Leader Create, Member Enter)
**Actor**: Leader account, then Member account  
**Steps**:
1. Login as Leader
2. Navigate to group tests
3. Tap "Create Test"
4. Enter test details
5. Add questions
6. Publish test
7. Login as Member
8. View available tests
9. Enter test
10. Answer questions
11. Submit test

**Expected Results**:
- [ ] Test creation interface accessible
- [ ] Test saved as draft
- [ ] Test published successfully
- [ ] Test appears in member's list
- [ ] Member can enter test
- [ ] Questions display correctly
- [ ] Answers recorded
- [ ] Submission successful

### Journey J: Results (Member View)
**Actor**: Member account  
**Prerequisites**: Test completed (Journey I)  
**Steps**:
1. Login as Member
2. Navigate to group results
3. View test results
4. Check score
5. View detailed breakdown

**Expected Results**:
- [ ] Results list accessible
- [ ] Test result displayed
- [ ] Score accurate
- [ ] Detailed breakdown available
- [ ] Correct answers highlighted

### Journey K: Leaderboard (Leader View)
**Actor**: Leader account  
**Prerequisites**: Tests completed by multiple members  
**Steps**:
1. Login as Leader
2. Navigate to group leaderboard
3. View rankings
4. Filter by time period
5. Verify accuracy

**Expected Results**:
- [ ] Leaderboard accessible
- [ ] Rankings displayed
- [ ] Rankings accurate
- [ ] Filtering works
- [ ] No performance issues

### Journey L: Notifications (Mark Read)
**Actor**: Member account  
**Prerequisites**: Notifications exist  
**Steps**:
1. Login as Member
2. View notification badge count
3. Open notifications
4. Mark individual notification as read
5. Mark all as read
6. Verify badge count updates

**Expected Results**:
- [ ] Badge count accurate
- [ ] Notification list accessible
- [ ] Individual mark read works
- [ ] Mark all as read works
- [ ] Badge count updates immediately

### Journey M: Leave/Remove
**Actor**: Member account, then Owner account  
**Steps**:
1. Login as Member
2. Navigate to group settings
3. Tap "Leave Group"
4. Confirm leave
5. Verify removed from group
6. Login as Owner
7. Navigate to group members
8. Select another member
9. Tap "Remove Member"
10. Confirm removal

**Expected Results**:
- [ ] Leave confirmation dialog
- [ ] Member successfully leaves
- [ ] Group removed from member's list
- [ ] Owner can access remove function
- [ ] Removal confirmation dialog
- [ ] Member removed successfully
- [ ] Notifications sent appropriately

## 7. Expected Results per Journey

| Journey | Expected Outcome |
|---------|-----------------|
| A: Group Creation | Group created, owner assigned, invite code generated |
| B: Member Join | Member added, public access successful |
| C: Invitation Flow | Invitation sent, accepted, member added |
| D: Join Request | Request submitted, approved, member added |
| E: Role Management | Role changed, permissions updated |
| F: Settings | Group details updated, changes reflected |
| G: Chat | Messages sent/received, pagination works |
| H: Announcements | Announcement created, visible to members |
| I: Tests | Test created, taken, submitted |
| J: Results | Results displayed accurately |
| K: Leaderboard | Rankings displayed correctly |
| L: Notifications | Notifications managed properly |
| M: Leave/Remove | Membership changes processed |

## 8. Cleanup

### Between Test Runs
1. **Reset Test Data**:
   ```sql
   -- Reset group to initial state
   UPDATE groups SET name = 'Test Study Group', description = 'Test group', privacy = 'public' WHERE id = 'test-group-001';
   
   -- Remove test-created groups
   DELETE FROM groups WHERE name LIKE '%E2E Test%';
   
   -- Reset member roles
   UPDATE group_members SET role = 'member' WHERE group_id = 'test-group-001';
   ```

2. **Remove Test Memberships**:
   ```sql
   DELETE FROM group_members WHERE user_id IN ('test-member-001', 'test-member-002', 'test-member-003');
   ```

3. **Clear Test Data**:
   ```sql
   DELETE FROM group_chat WHERE group_id = 'test-group-001';
   DELETE FROM group_announcements WHERE group_id = 'test-group-001';
   DELETE FROM group_rules WHERE group_id = 'test-group-001';
   DELETE FROM group_tests WHERE group_id = 'test-group-001';
   DELETE FROM group_test_results WHERE group_id = 'test-group-001';
   ```

### Full Reset
- Re-run G1-G17 migrations
- Re-seed test data
- Verify RLS policies

## 9. Backend Dependencies

### Supabase RPCs
| RPC | Purpose | G17 Affected |
|-----|---------|--------------|
| `create_group` | Create new group | Yes |
| `join_group` | Join public group | No |
| `request_join_group` | Request to join private group | No |
| `invite_to_group` | Send invitation | No |
| `approve_join_request` | Approve pending request | No |
| `remove_member` | Remove member from group | No |
| `change_member_role` | Update member role | No |
| `update_group_settings` | Edit group details | No |
| `create_group_rule` | Add rule | No |
| `delete_group_rule` | Remove rule | No |
| `create_announcement` | Post announcement | No |
| `send_chat_message` | Send chat message | No |
| `create_group_test` | Create test | No |
| `submit_test_answers` | Submit test | No |

### RLS Policies
| Policy | Table | G17 Affected |
|--------|-------|--------------|
| `groups_select` | groups | Yes |
| `groups_insert` | groups | Yes |
| `groups_update` | groups | Yes |
| `groups_delete` | groups | Yes |
| `group_members_select` | group_members | Yes |
| `group_members_insert` | group_members | Yes |
| `group_members_update` | group_members | Yes |
| `group_members_delete` | group_members | Yes |
| `group_chat_select` | group_chat | No |
| `group_chat_insert` | group_chat | No |
| `group_announcements_select` | group_announcements | No |
| `group_announcements_insert` | group_announcements | No |
| `group_rules_select` | group_rules | No |
| `group_rules_insert` | group_rules | No |
| `group_tests_select` | group_tests | No |
| `group_tests_insert` | group_tests | No |

### G17 Migration Impact
- **G17_001**: Groups table RLS policies
- **G17_002**: Group members table RLS policies
- **G17_003**: Group chat table RLS policies
- **G17_004**: Group announcements table RLS policies
- **G17_005**: Group rules table RLS policies
- **G17_006**: Group tests table RLS policies
- **G17_007**: Performance indexes
- **G17_008**: Security audit findings

**Note**: G17 fixes may affect RLS policy behavior and require re-testing of permission boundaries.

## 10. Known Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| No ownership transfer | Owner cannot transfer ownership to another member | Manual database update required |
| No real-time chat | Chat messages require manual refresh | Pull-to-refresh or re-enter chat |
| No group deletion from client | Groups cannot be deleted via app | Database deletion or admin panel |
| Logo upload not yet supported | Groups cannot have custom logos | Use default avatar |

## 11. G17 Dependency

### Required Migrations
| Migration | Description | Status |
|-----------|-------------|--------|
| G17_001 | Groups table RLS policies | ☐ Applied |
| G17_002 | Group members table RLS policies | ☐ Applied |
| G17_003 | Group chat table RLS policies | ☐ Applied |
| G17_004 | Group announcements table RLS policies | ☐ Applied |
| G17_005 | Group rules table RLS policies | ☐ Applied |
| G17_006 | Group tests table RLS policies | ☐ Applied |
| G17_007 | Performance indexes | ☐ Applied |
| G17_008 | Security audit findings | ☐ Applied |

### Security Verdict
- **Status**: PENDING
- **Auditor**: ____________
- **Date**: ____________
- **Notes**: ____________

**⚠️ G18 acceptance testing is provisional until G17 security audit completes with PASS verdict.**

---

**Document Version**: 1.0  
**Last Updated**: [Date]  
**Author**: [Name]  
**Status**: Draft