# Notification System V1 - Event Catalog

## Canonical Notification Events

This document defines all notification events supported by the "My Preparation" notification system. Events are generated server-side via triggers and cron jobs.

---

## ACCOUNT Events
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Welcome | `SYSTEM_NOTIFICATION` | User signup (via `fn_ensure_notification_settings`) | `/notifications` |
| Security alert | `SYSTEM_NOTIFICATION` | Server-side security events | `/notifications` |

---

## GROUP Events

### Membership
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Group invitation received | `GROUP_ANNOUNCEMENT` | `fn_notify_group` via invitation flow | `/groups/:groupId` |
| Invitation accepted | `GROUP_JOIN` | `trg_notify_group_join` | `/groups/:groupId` |
| Invitation declined | - | No notification (private action) | - |
| Join request received | `GROUP_ANNOUNCEMENT` | Join request flow | `/groups/:groupId` |
| Join request approved | `GROUP_JOIN` | `fn_approve_group_join_request` | `/groups/:groupId` |
| Join request rejected | - | No notification (private action) | - |
| Member joined | `GROUP_JOIN` | `trg_notify_group_join` | `/groups/:groupId` |
| Member left | - | No notification (private action) | - |
| Member removed | - | No notification (private action) | - |
| Role changed | `GROUP_ANNOUNCEMENT` | Role update flow | `/groups/:groupId` |

### Group Activity
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| New message | `GROUP_MESSAGE` | `trg_notify_group_message` | `/groups/:groupId` |
| New announcement | `GROUP_ANNOUNCEMENT` | `trg_notify_group_announcement` | `/groups/:groupId` |
| Group settings changed | `GROUP_ANNOUNCEMENT` | Settings update flow | `/groups/:groupId/settings` |

### Group Tests
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Test created | `TEST_INVITATION` | `trg_notify_group_test` | `/groups/:groupId/tests` |
| Test assigned | `GROUP_TEST_ASSIGNED` | Assignment flow | `/tests/:testId` |
| Test reminder | `GROUP_TEST_REMINDER` | `fn_send_test_reminders` | `/tests/:testId` |

---

## TEST Events

### Lifecycle
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Test scheduled | `TEST_SCHEDULED` | Test creation with `starts_at` | `/tests/:testId` |
| Test starting soon | `TEST_STARTING_SOON` | `fn_send_test_reminders` (24h) | `/tests/:testId` |
| Test starts in 1 hour | `TEST_REMINDER` | `fn_send_test_reminders` (1h) | `/tests/:testId` |
| Test starts in 10 minutes | `TEST_LIVE` | `fn_send_test_reminders` (10m) | `/tests/:testId` |
| Test started/live | `TEST_STARTED` | Status transition | `/tests/:testId` |
| Test ended | `TEST_ENDED` | Status transition | `/tests/:testId` |
| Test cancelled | - | Status transition | - |

### Results
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Result generated | `TEST_COMPLETED` | Attempt submission | `/attempts/:attemptId/result` |
| Result available | `RESULTS_AVAILABLE` | Result processing complete | `/tests/:testId` |
| Leaderboard updated | `LEADERBOARD_UPDATED` | Result batch complete | `/tests/:testId/results/leaderboard` |

### Assignments
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Assignment created | `GROUP_TEST_ASSIGNED` | Assignment flow | `/tests/:testId` |
| Assignment reminder | `GROUP_TEST_REMINDER` | `fn_send_test_reminders` | `/tests/:testId` |

---

## ROUTINE / STUDY Events
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Study session reminder | `ROUTINE_REMINDER` | `fn_send_routine_reminders` | `/routine` |
| Routine item due | `ROUTINE_DUE` | Cron check | `/routine/:routineId` |
| Routine completed | `ROUTINE_COMPLETED` | User marks complete | `/routine` |
| Routine missed | `ROUTINE_MISSED` | Cron check (past due) | `/routine` |
| Streak milestone | `STREAK_MILESTONE` | `fn_user_streak` check | `/performance` |

---

## AI Events
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| AI generation completed | `CONTENT_REVIEW_RESULT` | Next.js API callback | `/tests/:testId` |
| AI generation failed | `SYSTEM_NOTIFICATION` | Next.js API error | `/notifications` |
| AI Coach Report ready | `REPORT_READY` | Report generation complete | `/performance` |

---

## SYSTEM Events
| Event | Category | Trigger | Deep Link |
|-------|----------|---------|-----------|
| Maintenance notice | `SYSTEM_NOTIFICATION` | Server-side | `/notifications` |
| Security alert | `SYSTEM_NOTIFICATION` | Server-side | `/notifications` |

---

## Event Properties

Every notification row contains:

| Property | Source | Purpose |
|----------|--------|---------|
| `id` | Auto-generated UUID | Primary key |
| `user_id` | Server-derived (`auth.uid()`) | Recipient |
| `category` | `notif_category` enum | Event type |
| `title` | Server-generated | Display title |
| `body` | Server-generated | Display body |
| `data` | JSONB payload | Metadata (IDs, deep links, etc.) |
| `read_at` | Client-set on read | Read state |
| `created_at` | Server-generated | Timestamp |
| `priority` | Server-generated | `low`, `medium`, `high`, `urgent` |
| `dedupe_key` | Server-generated | Idempotency key |

### Data Payload Keys
| Key | Type | Description |
|-----|------|-------------|
| `group_id` | UUID | Group scope (for group notifications) |
| `type` | String | Legacy type identifier |
| `deep_link` | String | Navigation path |
| `test_id` | UUID | Test reference |
| `routine_id` | UUID | Routine reference |
| `message_id` | UUID | Chat message reference |
| `announcement_id` | UUID | Announcement reference |
| `idempotency_key` | String | Deduplication key |
| `reminder` | String | Reminder timing (24h, 1h, 10m) |
| `spec_type` | String | Spec type identifier |

---

## Deduplication Rules

| Event | Dedupe Key Pattern |
|-------|-------------------|
| Test reminder | `test:{test_id}:{reminder_key}` |
| Routine reminder | `routine:{routine_id}:{date}` |
| Group message | `data->>'message_id'` |
| Group announcement | `data->>'announcement_id'` |

---

## Suppression Rules

1. **Muted group**: All group notifications suppressed
2. **Category toggle**: Category-specific notifications suppressed
3. **Master toggle**: All notifications suppressed
4. **Quiet hours**: Non-high-priority notifications suppressed
5. **Self-notification**: Sender excluded from own notifications
6. **Duplicate**: Same event not sent twice (idempotency)
