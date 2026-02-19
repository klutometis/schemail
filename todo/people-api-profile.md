# Google People API - Get User Profile Name

## Problem

When drafting email replies, we need the user's actual name for signatures. Currently we have no good way to get this.

**Bad approaches (do NOT use):**
- ❌ Extract from email address (unreliable - `you@example.com` could be anyone)
- ❌ Ask user to set `USER_NAME` env var (annoying manual config)
- ❌ Let Claude "figure it out" from email (impossible/unreliable)

**Good approach:**
- ✅ Use Google People API to get authenticated user's profile

## Solution: Google People API

The People API provides access to the authenticated user's profile information including their display name.

### API Endpoint

```
GET https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses
```

### Required OAuth Scope

Add to existing scopes in `src/oauth.rkt`:

```racket
(define gmail-scopes
  (list "https://www.googleapis.com/auth/gmail.readonly"
        "https://www.googleapis.com/auth/gmail.modify"
        "https://www.googleapis.com/auth/gmail.labels"
        "https://www.googleapis.com/auth/userinfo.profile"))  ; NEW
```

### Response Format

```json
{
  "resourceName": "people/1234567890",
  "etag": "...",
  "names": [
    {
      "metadata": {
        "primary": true,
        "source": {
          "type": "PROFILE",
          "id": "1234567890"
        }
      },
      "displayName": "Peter Danenberg",
      "familyName": "Danenberg",
      "givenName": "Peter",
      "displayNameLastFirst": "Danenberg, Peter"
    }
  ],
  "emailAddresses": [
    {
      "metadata": {
        "primary": true,
        "verified": true,
        "source": {
          "type": "ACCOUNT",
          "id": "1234567890"
        }
      },
      "value": "you@example.com"
    }
  ]
}
```

### Implementation

**New file:** `src/people.rkt`

```racket
#lang racket

(require "oauth.rkt"
         json
         net/http-easy)

;; Get user profile from People API
(define (people-get-profile)
  (define token (get-gmail-token))
  (define response
    (get "https://people.googleapis.com/v1/people/me"
         #:params (hash 'personFields "names,emailAddresses")
         #:headers (hash 'authorization (format "Bearer ~a" 
                                                (token-access token)))))
  (response-json response))

;; Extract display name from profile
(define (people-get-display-name)
  (define profile (people-get-profile))
  (define names (hash-ref profile 'names '()))
  (if (empty? names)
      #f  ; No name available
      (hash-ref (first names) 'displayName #f)))

;; Extract given name (first name)
(define (people-get-given-name)
  (define profile (people-get-profile))
  (define names (hash-ref profile 'names '()))
  (if (empty? names)
      #f
      (hash-ref (first names) 'givenName #f)))

(provide people-get-profile
         people-get-display-name
         people-get-given-name)
```

### Usage in `schemail-flow`

```racket
;; At startup, get user's name
(define user-display-name (people-get-display-name))
(displayln (format "Logged in as: ~a (~a)" 
                   user-email 
                   (or user-display-name "name unknown")))

;; When drafting reply, pass name
(define draft (draft-reply msg 
                          #:user-email user-email
                          #:user-name (or user-display-name "")))
```

### Update reply prompt

```racket
(define prompt
  (format "You are an email reply assistant. Draft a professional, concise email reply.

YOU ARE: ~a ~a

ORIGINAL EMAIL:
...

INSTRUCTIONS:
...
5. Sign with: ~a

Reply:"
          user-email
          (if (string=? user-name "") "" (format "(~a)" user-name))
          (if (string=? user-name "") "Best" user-name)))
```

## Migration Plan

1. Add People API scope to OAuth config
2. Re-authorize (delete token cache, run again)
3. Implement `src/people.rkt` 
4. Update `schemail-flow` to fetch name at startup
5. Update reply prompt to use real name

## Fallback

If People API call fails or returns no name:
- Draft unsigned replies
- User adds signature manually when editing in $EDITOR

## Notes

- This is the **proper** way to get user info
- No heuristics, no guessing
- Uses official Google API
- Name comes from user's Google Account profile

## References

- [People API - Get Profile](https://developers.google.com/people/api/rest/v1/people/get)
- [OAuth Scopes](https://developers.google.com/identity/protocols/oauth2/scopes)
