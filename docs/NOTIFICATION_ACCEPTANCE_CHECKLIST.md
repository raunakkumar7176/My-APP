# Notification System V1 - Acceptance Checklist

## Manual Testing Checklist

### 1. Authentication & Isolation
- [ ] Login as User A → receive notifications
- [ ] Logout
- [ ] Login as User B → User A's notifications MUST NOT appear
- [ ] Verify no notification leakage between accounts

### 2. Global Notification Center
- [ ] Open notification center from AppBar bell
- [ ] Open notification center from drawer
- [ ] Open notification center from settings
- [ ] Verify "All" tab shows all notifications
- [ ] Verify "Unread" tab shows only unread
- [ ] Verify unread count badge on bell icon
- [ ] Verify unread count in AppBar title
- [ ] Pull-to-refresh works
- [ ] Load older notifications (pagination)
- [ ] Empty state shows when no notifications

### 3. Mark Read/Unread
- [ ] Tap notification → marks as read
- [ ] Mark all read button works
- [ ] Unread dot disappears after marking read
- [ ] Unread count updates after mark read
- [ ] Unread count updates after mark all read

### 4. Notification Preferences
- [ ] Open notification settings from notification center
- [ ] Toggle master switch OFF → all categories disabled
- [ ] Toggle master switch ON → categories re-enabled
- [ ] Toggle individual categories (group chat, announcements, tests, routine, AI, system)
- [ ] Settings persist after app restart
- [ ] Quiet hours toggle works
- [ ] Quiet hours time display shows correctly

### 5. Group Notifications
- [ ] Receive group message notification
- [ ] Receive group announcement notification
- [ ] Receive group join notification
- [ ] Receive test invitation notification
- [ ] Group mute toggle works
- [ ] Muted group → no new notifications
- [ ] Per-group notification screen still works

### 6. Test Notifications
- [ ] Test created → notification for group members
- [ ] Test reminder (24h, 1h, 10m) → notification
- [ ] Test result available → notification
- [ ] Test assigned → notification

### 7. Routine Notifications
- [ ] Routine reminder → notification
- [ ] Routine completed → no duplicate reminder
- [ ] Deleted routine → no future reminders

### 8. Deep Link Navigation
- [ ] Tap group notification → navigates to group
- [ ] Tap test notification → navigates to test
- [ ] Tap routine notification → navigates to routine
- [ ] Tap announcement notification → navigates to announcement
- [ ] Invalid deep link → fallback to notification center
- [ ] Deleted object → shows error state

### 9. Light/Dark Mode
- [ ] Notification center works in light mode
- [ ] Notification center works in dark mode
- [ ] Category icons visible in both modes
- [ ] Unread indicator visible in both modes

### 10. Error Handling
- [ ] Network error → retry button works
- [ ] Empty state shows appropriate message
- [ ] Loading state shows spinner
- [ ] Permission denied → appropriate error message

### 11. Performance
- [ ] Pagination loads 30 items per page
- [ ] No duplicate notifications in list
- [ ] Scroll performance smooth with many notifications
- [ ] Unread count query is fast (server-side)

### 12. Security
- [ ] Cannot read other user's notifications
- [ ] Cannot mark other user's notifications read
- [ ] Cannot inject arbitrary notifications
- [ ] RLS enforced on all operations
- [ ] Deep link re-checks authorization at destination

### 13. Push Notifications (When Firebase is Configured)
- [ ] Foreground: notification updates center
- [ ] Background: notification opens correct screen
- [ ] Terminated: notification opens correct screen
- [ ] Token refresh works
- [ ] Logout cleans up tokens
- [ ] Invalid token handled gracefully

### 14. Cleanup
- [ ] Read notifications older than 30 days are cleaned
- [ ] Stale dedupe keys cleared after 7 days
- [ ] Cleanup runs every 6 hours
- [ ] Unread notifications are NOT deleted

---

## Automated Test Coverage

### Unit Tests
- `test/group/group_notifications_test.dart` - Per-group notification screen
- `test/app_routes_test.dart` - Route validation

### Widget Tests
- Notification tile rendering
- Notification center tabs
- Settings toggles
- Empty/error/loading states

### Integration Tests
- Mark read flow
- Mark all read flow
- Deep link navigation
- Settings persistence
