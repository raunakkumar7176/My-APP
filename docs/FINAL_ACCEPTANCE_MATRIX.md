# Final Acceptance Matrix

**Status:** NOT PRODUCTION READY — preparation complete, device acceptance pending

---

## A. Backend Security Gate

| # | Requirement | Current State | Evidence | Owner | Status | Blocker | Next Action |
|---|---|---|---|---|---|---|---|
| A1 | P0 security gaps = 0 | Verified | `ec8f5a0` commit message | Backend | PASS | No | — |
| A2 | P1 security gaps = 0 | Verified | `ec8f5a0` commit message | Backend | PASS | No | — |
| A3 | All security migrations applied live | Verified | `ec8f5a0` commit message | Backend | PASS | No | — |
| A4 | `rpc_get_leaderboard` is SECURITY DEFINER | Verified | Backend audit report | Backend | PASS | No | — |
| A5 | `fn_accept_group_invitation(p_invitation_id)` live | Verified | Backend audit report | Backend | PASS | No | — |
| A6 | `fn_withdraw_join_request` verified | Verified | Backend audit report | Backend | PASS | No | — |
| A7 | G6 rules backend live | Verified | Backend audit report | Backend | PASS | No | — |
| A8 | G11 coach-report request RPC live | Verified | Backend audit report | Backend | PASS | No | — |
| A9 | Anon cannot read leaderboard | Verified | Backend audit report | Backend | PASS | No | — |
| A10 | Legacy lifecycle guard live | Verified | Backend audit report | Backend | PASS | No | — |

---

## B. Flutter Functional Gate

| # | Requirement | Current State | Evidence | Owner | Status | Blocker | Next Action |
|---|---|---|---|---|---|---|---|
| B1 | `flutter analyze`: 0 errors, 0 warnings | Verified | Analyzer output | Flutter | PASS | No | — |
| B2 | `flutter test`: all pass | Verified | 998 pass, 0 fail | Flutter | PASS | No | — |
| B3 | APK builds successfully | Verified | `app-debug.apk` built | Flutter | PASS | No | — |
| B4 | F-06: `p_invitation_id` parameter | Verified | `group_repository.dart:618,627` | Flutter | PASS | No | — |
| B5 | F-10: member sees "Your result" only | Fixed | Screen conditional header | Flutter | PASS | No | — |
| B6 | F-10: owner/analytics sees full ranking | Fixed | Screen conditional header | Flutter | PASS | No | — |
| B7 | F-10: `canSeeFullLeaderboard` permission probe | Verified | Controller `load()` | Flutter | PASS | No | — |
| B8 | F-11: `deleted_at` in model | Verified | `GroupMessage.deletedAt` | Flutter | PASS | No | — |
| B9 | F-11: `_messageColumns` includes `deleted_at` | Verified | `group_repository.dart:966` | Flutter | PASS | No | — |
| B10 | F-11: "Message deleted" placeholder | Verified | `group_chat_section.dart:185-221` | Flutter | PASS | No | — |
| B11 | G6 rules: full CRUD | Verified | Repository + controller + widget | Flutter | PASS | No | — |
| B12 | G11 coach reports: request flow | Verified | Controller + screen | Flutter | PASS | No | — |
| B13 | All routes registered | Verified | `app_router.dart` | Flutter | PASS | No | — |
| B14 | Cross-group isolation | Verified | Tests pass | Flutter | PASS | No | — |

---

## C. Device Acceptance Gate

| # | Requirement | Current State | Evidence | Owner | Status | Blocker | Next Action |
|---|---|---|---|---|---|---|---|
| C1 | 66-item checklist prepared | Verified | `G18_DEVICE_ACCEPTANCE_CHECKLIST.md` | QA | PASS | No | — |
| C2 | Runbook prepared | Verified | `FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md` | QA | PASS | No | — |
| C3 | All items unverified | Verified | No PASS markings | QA | PASS | No | — |
| C4 | Physical device execution | Not started | — | QA | **BLOCKED** | **Yes** | Execute on device |

---

## D. Credential / Security Hygiene Gate

| # | Requirement | Current State | Evidence | Owner | Status | Blocker | Next Action |
|---|---|---|---|---|---|---|---|
| D1 | No secrets in Flutter code | Verified | Git diff audit | Flutter | PASS | No | — |
| D2 | No plaintext credentials committed | Verified | Git status | Flutter | PASS | No | — |
| D3 | `tool/` not tracked | Verified | `.gitignore` check needed | Flutter | **BLOCKED** | **Yes** | Add to gitignore |
| D4 | Credential rotation documented | Verified | `CREDENTIAL_ROTATION_RUNBOOK.md` | Flutter | PASS | No | — |
| D5 | No `node_modules/` committed | Verified | Git status | Flutter | PASS | No | — |

---

## E. Product Decision Gate

| # | Requirement | Current State | Evidence | Owner | Status | Blocker | Next Action |
|---|---|---|---|---|---|---|---|
| E1 | F-10 UX decision locked | Verified | "Your result" for members | Product | PASS | No | — |
| E2 | F-11 UX decision locked | Verified | "Message deleted" placeholder | Product | PASS | No | — |
| E3 | Owner transfer: not implemented | Verified | Not in scope | Product | PASS | No | Future roadmap |
| E4 | Group deletion: not implemented | Verified | Not in scope | Product | PASS | No | Future roadmap |
| E5 | Logo upload: not implemented | Verified | Not in scope | Product | PASS | No | Future roadmap |
| E6 | AI worker: not implemented | Verified | No worker exists | Product | PASS | No | Future roadmap |

---

## Summary

| Gate | Status |
|---|---|
| A. Backend Security | PASS (10/10) |
| B. Flutter Functional | PASS (14/14) |
| C. Device Acceptance | BLOCKED (physical device needed) |
| D. Credential Hygiene | BLOCKED (tool/ gitignore needed) |
| E. Product Decisions | PASS (6/6) |

**Overall:** FINAL ACCEPTANCE PREPARATION COMPLETE WITH FINDINGS

Physical device acceptance remains pending until a real Android device executes all 66 checks.
Credential hygiene requires adding `tool/` to `.gitignore`.
