# People API Setup

## What Changed

Added support for Google People API to get your display name for email signatures.

### New Features
1. **People API integration** (`src/people.rkt`)
   - Fetches your display name from Google profile
   - Formats email addresses as `"Name <email@domain.com>"`

2. **Better reply-from addresses**
   - Uses "Delivered-To" header (handles To/Cc/Bcc correctly)
   - Includes your display name in From field
   - Before: `you@example.com`
   - After: `Your Name <you@example.com>`

3. **Improved AI signatures**
   - Claude now knows your actual name
   - Signs replies with your name instead of guessing from email

## Re-authorization Required

The new People API scope requires re-authorization:

```bash
# Delete existing token to force re-auth
rm ~/.oauth2.rkt/tokens

# Run any command that needs auth (will open browser)
racket bin/schemail-flow
```

When you authorize, you'll see a new permission:
- ✅ "View your basic profile info" (userinfo.profile scope)

This allows the app to read your display name from your Google Account.

## How It Works

### CC/BCC Handling

The code now uses the "Delivered-To" header instead of "To":

**Problem with "To" header:**
- Email to: `john@example.com`
- CC: `you@example.com`
- "To" header: `john@example.com` ❌ (would reply as John!)

**Solution with "Delivered-To":**
- "Delivered-To" header: `you@example.com` ✓ (correct!)

### Display Name

```racket
;; Fetch from People API
(define user-display-name (people-get-display-name))
;; => "Your Name"

;; Format with email
(format-email-with-name "you@example.com" user-display-name)
;; => "Your Name <you@example.com>"
```

### AI Integration

The reply drafter now receives your name:

```racket
(draft-reply msg
             #:user-email "you@example.com"
             #:user-name "Your Name")
```

Claude's prompt includes:
```
YOU ARE: you@example.com (Your Name)

INSTRUCTIONS:
...
5. Sign with: Your Name
```

## Fallback Behavior

If People API fails or returns no name:
- From field: bare email address
- AI signature: "Best" instead of name
- Everything still works, just without the name

## Testing

After re-authorizing:

```bash
# Test People API
racket -e "(require \"src/people.rkt\" \"src/oauth.rkt\") \
           (get-gmail-token) \
           (displayln (people-get-display-name))"
# Should output: Your Name

# Test schemail-flow
bin/schemail-flow
# Should show: Logged in as: you@example.com (Your Name)
```

## Files Changed

- `src/oauth.rkt` - Added `userinfo.profile` scope
- `src/people.rkt` - New People API module
- `src/reply-drafter.rkt` - Accept and use `user-name` parameter
- `bin/schemail-flow` - Use Delivered-To + display name
