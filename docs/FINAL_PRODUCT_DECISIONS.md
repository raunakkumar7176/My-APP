# Final Product Decision Register

**Purpose:** Record unresolved product decisions that remain before production acceptance.

---

## Resolved Product Decisions (Locked)

These decisions are locked and implemented. No further action needed.

### F-10: Leaderboard UX for Ordinary Members

| Field | Value |
|---|---|
| Decision | Ordinary members see "Your result" + score/percentage only. No rank, no participant count, no other users' entries. Owner and analytics holders see full leaderboard. |
| Rationale | Members should not see other participants' scores. Full ranking is for group managers only. |
| Implementation | `GroupLeaderboardController.canSeeFullLeaderboard` + conditional screen rendering |
| Status | LOCKED — Implemented |

### F-11: Deleted Chat Message UX

| Field | Value |
|---|---|
| Decision | Soft-deleted messages show "Message deleted" italic placeholder. Row is never hidden. Original body is never rendered. |
| Rationale | Hiding rows creates confusion. Placeholder preserves chat flow context. |
| Implementation | `GroupMessage.isDeleted` + `_bubble()` conditional rendering |
| Status | LOCKED — Implemented |

### Owner Transfer

| Field | Value |
|---|---|
| Decision | Not implemented in current scope |
| Rationale | Complex multi-step flow requiring backend support, confirmation, and audit trail |
| Status | Future roadmap |

### Group Deletion

| Field | Value |
|---|---|
| Decision | Not implemented in current scope |
| Rationale | Requires cascading deletes, member notification, and soft-delete semantics |
| Status | Future roadmap |

### Group Logo Upload

| Field | Value |
|---|---|
| Decision | Not implemented in current scope |
| Rationale | Requires storage integration, image processing, and CDN setup |
| Status | Future roadmap |

### AI Worker (Coach Reports)

| Field | Value |
|---|---|
| Decision | No AI worker implemented. `rpc_request_coach_reports` queues jobs. UI shows queued/pending state. No report content is generated. |
| Rationale | AI worker is out of scope for current phase. Queue mechanism is in place for future activation. |
| Status | Future roadmap |

---

## Unresolved Product Decisions

None at this time. All critical decisions are locked.

---

## Future Roadmap Items

These items are NOT blockers for production acceptance. They are future enhancements.

1. **Owner Transfer** — Allow owner to transfer ownership to another member
2. **Group Deletion** — Soft-delete groups with cascading effects
3. **Logo Upload** — Storage-backed group logo with image processing
4. **AI Worker** — Background job processor for coach reports
5. **Real-time Chat** — Supabase Realtime for live message delivery
6. **Push Notifications** — FCM/APNs integration for mobile notifications
