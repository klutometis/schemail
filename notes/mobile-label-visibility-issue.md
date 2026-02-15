# Mobile Label Visibility Issue

## Problem Discovered (2026-02-15)

**Issue:** Gmail mobile app doesn't respect `labelListVisibility: labelHide` setting.

**Current behavior:**
- Desktop Gmail: Schemail marker label is hidden ✅
- Mobile Gmail: Schemail marker label is VISIBLE ❌
- Result: All emails show "Schemail" label in mobile app

**User experience impact:**
- Schemail label clutters mobile label view
- No functional problem (just visual noise)
- Degrades the clean Inbox Zero aesthetic

## Current Implementation

We use a hidden `Schemail` marker label to track processed emails:

```racket
;; Create hidden marker
(gmail-create-label "Schemail"
  #:labelListVisibility "labelHide"     ; Hide from sidebar
  #:messageListVisibility "hide")       ; Hide from message list
```

**Query for unprocessed emails:**
```
in:inbox -label:Schemail
```

**Why we need a marker:**
- Track which emails have been classified
- Skip them on subsequent runs
- Allow manual labeling without marking as "processed"
- Works great on desktop ✅
- Broken on mobile ❌

## Alternative Solutions

### Option 1: Live with it (Current)

**Pros:**
- No code changes needed
- Works perfectly on desktop
- Functionally correct

**Cons:**
- ❌ Ugly on mobile
- User sees "Schemail" on every processed email

**Verdict:** Current state, but not ideal

---

### Option 2: Use `has:userlabels` Query

**Implementation:**
Change query from `-label:Schemail` to `-has:userlabels`

**Pros:**
- ✅ No marker label needed
- ✅ No mobile visibility issue
- ✅ Clean on all devices
- ✅ Simple query

**Cons:**
- ❌ Can't manually label emails without marking them as "processed"
- ❌ If user adds any label to an email, it won't be reprocessed
- ❌ Less flexible workflow

**Example scenario:**
```
User manually adds "Important" label to email
→ Email now has a user label
→ Query -has:userlabels skips it
→ Email never gets classified by Schemail
```

**Verdict:** Too rigid, breaks manual labeling workflow

---

### Option 3: Prefix All Labels (Schemail/Newsletter)

**Implementation:**
Return to hierarchical `Schemail/*` structure without parent:

```racket
;; Create labels like:
Schemail/Newsletter
Schemail/Receipt
Schemail/Events
```

**Query:**
```
-label:Schemail/Newsletter -label:Schemail/Receipt -label:Schemail/Events ...
```

**Pros:**
- ✅ No separate marker label
- ✅ Clear "Schemail touched this" semantics
- ✅ Works on mobile

**Cons:**
- ❌ Query is O(n) for number of label types
- ❌ Less clean aesthetically (Schemail/ prefix everywhere)
- ❌ Requires code changes
- ❌ Breaks existing flat label structure

**Verdict:** Works but uglier than current approach

---

### Option 4: Check for ANY User Label (Recommended)

**Implementation:**
Instead of checking for specific `Schemail` label, check for ANY user-created label:

```racket
;; In Gmail API, check if email has any labels except system labels
(define (email-has-user-labels? message)
  (define label-ids (message-label-ids message))
  (define user-labels 
    (filter (lambda (id) 
              (not (or (equal? id "INBOX")
                       (equal? id "UNREAD")
                       (equal? id "STARRED")
                       (equal? id "SENT")
                       (equal? id "DRAFT")
                       (equal? id "TRASH")
                       (equal? id "SPAM")
                       (equal? id "IMPORTANT"))))
            label-ids))
  (not (empty? user-labels)))
```

**Gmail query equivalent:**
```
in:inbox -has:userlabels
```

**Or with label filtering:**
```racket
;; Fetch emails, then filter in code
;; Only process if: no user labels OR only excluded labels
```

**Pros:**
- ✅ No visible marker label (solves mobile issue!)
- ✅ Clean on all devices
- ✅ Simpler than explicit marker
- ✅ Works with existing label structure

**Cons:**
- ⚠️ Any user label = "processed"
- ⚠️ Can't manually label an email and still have it processed
- ⚠️ Need to handle excluded labels (Groups, Saved) separately

**Workflow impact:**
```
Scenario A: User labels email manually
→ Email has user label
→ Skipped on next run ✅ (probably what you want)

Scenario B: User wants to reprocess labeled email
→ Remove all labels first
→ Run schemail
→ Gets new classification ✅
```

**Verdict:** Best balance of simplicity and functionality

---

### Option 5: Hybrid - Check for Any Label OR Marker

**Implementation:**
Allow either:
1. Email has the `Schemail` marker (processed by schemail), OR
2. Email has any other user label (manually labeled = processed)

```racket
(define (email-is-processed? message excluded-labels)
  (define label-ids (message-label-ids message))
  (define label-names (map label-id->name label-ids))
  (define user-labels
    (filter (lambda (name)
              (and (not (system-label? name))
                   (not (member name excluded-labels))))
            label-names))
  (or (member "Schemail" label-names)
      (not (empty? user-labels))))
```

**Gmail query (approximation):**
```
in:inbox -has:userlabels
```
Then filter out excluded labels in code.

**Pros:**
- ✅ Works with or without Schemail marker
- ✅ Manual labels = "don't touch this"
- ✅ Respects excluded labels (Groups, Saved)
- ✅ Most flexible

**Cons:**
- ⚠️ More complex logic
- ⚠️ Can't query purely with Gmail syntax (need code filtering)
- ⚠️ Schemail marker still visible on mobile (doesn't solve original issue)

**Verdict:** Most robust but doesn't solve mobile visibility

---

## Recommendation: Option 4 (Any User Label = Processed)

**Switch from:**
```
Query: in:inbox -label:Schemail
```

**To:**
```
Query: in:inbox -has:userlabels
```

**Implementation steps:**
1. Update default query in `bin/schemail` to use `-has:userlabels`
2. Remove `Schemail` marker label creation from `label-utils.rkt`
3. Update `apply-content-and-marker-labels` to only apply content label
4. Test on 50 emails to ensure behavior is correct
5. Update documentation to reflect new approach

**Migration for existing users:**
1. Optional: Manually delete `Schemail` label (will make all emails "unprocessed")
2. Or: Keep it, but new emails won't get it

**Trade-offs accepted:**
- Manual labeling = "processed" (probably desired behavior anyway)
- Need to remove all labels to reprocess (acceptable)
- Simpler overall system

**User workflow becomes:**
```
New email arrives
  ↓
Schemail processes (adds label like "Events")
  ↓
Email now has user label
  ↓
Subsequent runs skip it (has label = processed)
  ↓
Clean on mobile! ✅
```

## TODO

- [ ] Implement Option 4 (any user label = processed)
- [ ] Update query to `-has:userlabels`
- [ ] Remove Schemail marker creation code
- [ ] Test on 50 emails to verify behavior
- [ ] Update README/QUICKSTART with new approach
- [ ] Add note about manual labeling workflow

## Related Files

- `src/label-utils.rkt` - Remove `ensure-schemail-marker`
- `bin/schemail` - Update default query
- `notes/label-structure.md` - Original design doc with alternatives

---

## Related Issue: OAuth Token Refresh Failures

**Problem:** OAuth access tokens expire after ~1 hour. Refresh sometimes fails during long batch runs.

**Current behavior:**
- Token expires mid-run (e.g., email 100/200)
- Refresh attempt fails silently
- Process freezes waiting for browser auth
- User must manually restart

**Improvements made:**
- Better error message when refresh fails
- Prompt user to press Enter before opening browser
- Clearer indication of what went wrong

**Still needed:**
- Investigate why `refresh-token` fails (API error? Network?)
- Add retry logic with exponential backoff
- Consider pre-emptive refresh at 50 minutes

**Workaround for now:**
- For large batches (200+ emails), run in smaller chunks
- Or: Be ready to re-auth in browser after ~1 hour
