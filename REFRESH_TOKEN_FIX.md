# Fix: Missing Refresh Token for Headless Server

## Problem
Your token file has no refresh token (`#f`), so the daemon can't automatically refresh and requires manual browser authorization every hour.

## Root Cause
Google doesn't return a refresh token because:
1. You've already authorized this app before
2. Google only provides refresh tokens on the **first** authorization (unless you force re-consent)
3. Your current token was created without properly forcing consent

## Solution: Force Fresh Authorization

### Option 1: Revoke and Re-authorize (Recommended)

1. **Revoke existing authorization** (on any machine with browser):
   - Go to: https://myaccount.google.com/permissions
   - Find your OAuth app
   - Click "Remove Access"

2. **Run fresh authorization** (must have display/browser access):
   ```bash
   cd /home/danenberg/prg/email
   racket src/force-reauth.rkt
   ```
   
   This will:
   - Delete your old token
   - Start fresh OAuth flow
   - Request `access_type=offline` and `prompt=consent`
   - Get a refresh token from Google

3. **Verify you got a refresh token**:
   ```bash
   racket src/diagnose-token.rkt
   ```
   
   Should show: `✓ Refresh token is present`

### Option 2: Authorize on Local Machine, Copy to Server

If your server is headless:

1. **On your local machine** (with browser):
   ```bash
   # Clone the repo or copy oauth.rkt
   racket src/force-reauth.rkt
   ```

2. **Copy the token file to server**:
   ```bash
   scp ~/.oauth2.rkt/tokens SERVER:~/.oauth2.rkt/tokens
   scp ~/.oauth2.rkt/preferences SERVER:~/.oauth2.rkt/preferences
   ```

3. **Verify on server**:
   ```bash
   racket src/diagnose-token.rkt
   ```

## Why This Happens

From Google OAuth docs:
> "A refresh token is only returned on the **first authorization** for a given client_id and user combination. If you've authorized the app before, you must explicitly request re-consent using `prompt=consent` or revoke previous authorization."

Your code already requests `prompt=consent` (oauth.rkt:56), but if you have an existing authorization, Google may still not return a refresh token unless you fully revoke first.

## After Fix

Once you have a refresh token:
- ✅ Token expires after ~1 hour
- ✅ Code automatically calls `refresh-token` (oauth.rkt:157)
- ✅ Gets new access token without user interaction
- ✅ Daemon runs indefinitely on headless server

## Testing the Fix

```bash
# Check current token status
racket src/diagnose-token.rkt

# Test refresh logic
racket src/test-refresh.rkt

# Run daemon (should work indefinitely now)
racket config/schemail.rkt
```
