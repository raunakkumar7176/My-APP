# Credential Rotation Runbook

**Status:** REQUIRED — plaintext credentials exist in `tool/` directory

---

## Current State

The `tool/` directory contains JavaScript utility scripts with hardcoded database credentials:
- **Host:** Supabase pooler endpoint
- **User:** `postgres.cnwtprexxjrajcdjhfsr`
- **Password:** _(plaintext in tool/*.js files)_
- **Database:** `postgres`

These files are:
- Currently untracked by git (`??` status)
- Not committed to the repository
- On disk in plaintext

---

## Rotation Steps

### Step 1: Rotate the credential in Supabase

1. Log in to Supabase Dashboard
2. Go to **Project Settings** → **Database** → **Database Passwords**
3. Click **Rotate password** (or generate a new one)
4. Copy the new password (it will only be shown once)

### Step 2: Update local secret storage

If using `dart-defines.dev.json` for Flutter:
```bash
# Update the database password in your local dart-defines
# DO NOT commit this file
```

If using environment variables:
```bash
export SUPABASE_DB_PASSWORD="new_password_here"
```

### Step 3: Remove plaintext credentials from tool/

Option A — Delete the files (recommended):
```bash
rm -rf tool/
```

Option B — Remove only the password lines from each file:
```bash
# Find all files with hardcoded passwords
grep -rl "RRaunak@7176" tool/
# Edit each file to remove or replace the password
```

### Step 4: Verify tool/ is gitignored

The `.gitignore` now includes `tool/`. Verify:
```bash
git status tool/
# Should show: tool/ (untracked)
# Should NOT show: tool/ (new file) after git add
```

### Step 5: Verify no credential in repository

```bash
# Search entire repo for the old password
git grep -r "RRaunak@7176"
# Should return nothing

# Also check tracked files
git ls-files | xargs grep -l "RRaunak@7176" 2>/dev/null
# Should return nothing
```

### Step 6: Run security checks

```bash
# Verify Flutter code has no secrets
git diff --cached | grep -i "password\|secret\|key\|token"
# Should return nothing (only widget keys, not API keys)
```

---

## Verification Checklist

- [ ] Supabase password rotated
- [ ] Local secret storage updated
- [ ] `tool/` directory deleted or passwords removed
- [ ] `.gitignore` includes `tool/`
- [ ] `git grep` finds no plaintext credentials
- [ ] `git ls-files` finds no plaintext credentials in tracked files
- [ ] Flutter code audit clean

---

## Important Notes

- **Never commit credentials** to the repository
- **Never print credentials** in logs or error messages
- **Rotate immediately** if credentials are suspected compromised
- The `tool/` directory was for backend testing only and is not needed for production
