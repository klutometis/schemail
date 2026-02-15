# OAuth Token Management Improvements

## Problem

The `simple-oauth2` package occasionally has token decryption failures:
```
decrypt: contract violation
  expected: input/c
  given: #f
```

Previously, this required **manual intervention**:
1. Delete `~/.oauth2.rkt/tokens`
2. Re-run the command
3. Complete OAuth flow

## Solution

**Automatic recovery** - added error handling in `get-gmail-token`:

### Token Decryption Failure
```racket
(with-handlers ([exn:fail? (λ (e)
                             (displayln "⚠ Token decryption failed (corrupted token file)")
                             (displayln "  Automatically re-authorizing...")
                             #f)])
  (get-token user-name "gmail"))
```

### Token Refresh Failure
```racket
(with-handlers ([exn:fail? (λ (e)
                             (displayln "⚠ Token refresh failed")
                             (displayln "  Automatically re-authorizing...")
                             (authorize-gmail))])
  (refresh-token (make-gmail-client) stored-token))
```

## User Experience

**Before:**
```bash
$ schemail labels assign-colors
decrypt: contract violation... [crash]
$ rm ~/.oauth2.rkt/tokens  # Manual step
$ schemail labels assign-colors  # Try again
Opening browser...
```

**After:**
```bash
$ schemail labels assign-colors
⚠ Token decryption failed (corrupted token file)
  Automatically re-authorizing...
Opening browser...
```

## Implementation

**File**: `src/oauth.rkt:126-147`

The `get-gmail-token` function now:
1. Wraps `get-token` call in error handler
2. Wraps `refresh-token` call in error handler
3. Both failures trigger automatic re-authorization
4. User just completes OAuth flow - no manual cleanup

## Why Token Decryption Fails

Still unclear, but suspected causes:
- Race conditions in `simple-oauth2` encryption
- File corruption during write
- Encryption key issues

The automatic recovery makes this a non-issue for users.
