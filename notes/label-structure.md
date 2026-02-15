# Label Structure Design

## The Problem

Gmail label hierarchy syntax (`Parent/Child`) **does not support hierarchical queries**:
- `label:Schemail` will NOT match `label:Schemail/Newsletter`
- To match "any Schemail label", you'd need: `-label:Schemail/Newsletter -label:Schemail/Receipt -label:Schemail/Shipping...`
- This is O(n) and unmaintainable

Therefore, if we want compound labels like `Schemail/Newsletter`, we'd need to apply **both**:
- `Schemail` (parent, for "processed" queries)
- `Schemail/Newsletter` (child, for classification)

This feels redundant and ugly.

---

## Option A: Compound Labels with Dual Application ❌

**Labels applied:** `Schemail` + `Schemail/Newsletter`

**Query:** `-label:Schemail`

**Pros:**
- Clear namespace
- Hierarchical UI organization

**Cons:**
- Redundant: two labels per email
- Visible redundancy (both show in UI)
- More verbose

**Verdict:** Rejected - too redundant

---

## Option B: Flat Labels + Hidden `Schemail` Marker ✅ **CHOSEN**

**Labels applied:** `Newsletter` + `Schemail` (hidden)

**Query:** `-label:Schemail`

**Pros:**
- Clean visible labels (colorful, simple)
- Clear "processed" semantics via hidden marker
- Can manually label emails without marking as processed
- Easy to see what model is doing (hide non-Schemail labels)
- True Inbox Zero aesthetic

**Cons:**
- Two labels per email (but one invisible)
- Extra API call per classification (negligible)

**Implementation:**
```racket
;; Content label (visible, colorful)
(define label "Newsletter")  ; from model

;; Apply both labels:
(gmail-modify-message msg-id 
  #:add-labels (list newsletter-id schemail-marker-id))

;; Schemail marker created once with:
(gmail-create-label "Schemail" 
  #:label-list-visibility "labelHide")
```

**Verdict:** ✅ Best balance of clean UI and explicit semantics

---

## Option C: Single Flat Labels Only (Pure Inbox Zero)

**Labels applied:** `Newsletter` (only)

**Query:** `has:userlabels` (any label = processed)

**Pros:**
- Absolute simplest
- True Inbox Zero style
- One label per email

**Cons:**
- Can't manually label emails without marking as processed
- No way to distinguish "schemail touched this" vs "I labeled this"
- Breaks if you label anything else

**Verdict:** Too fragile for manual labeling use case

---

## Option D: Compound Labels Only (No Parent)

**Labels applied:** `Schemail/Newsletter` (only)

**Query:** `-label:Schemail/Newsletter -label:Schemail/Receipt -label:Schemail/Shipping...`

**Cons:**
- Query is O(n) for number of label types
- Unmaintainable
- Have to enumerate all possible labels

**Verdict:** Impractical

---

## Decision: Option B (Flat + Hidden Marker)

### Visual Result

**In Gmail UI:**
```
Inbox
  [Newsletter] Email from NYTimes...
  [Receipt] Email from Anthropic API...
  [Shipping] Email from Amazon...
```

**Hidden from sidebar:** `Schemail` label

**Applied to each email:** `Newsletter + Schemail`, `Receipt + Schemail`, etc.

### Query Behavior

```bash
# Unprocessed emails (default)
in:inbox -label:Schemail

# All emails (including processed)
in:inbox
```

### Future: Model Overview

Hide all non-Schemail labels from sidebar → only see model's classifications.

Use Gmail label colors to make categories visually distinct.

---

## Migration Notes

If changing from `Schemail/*` compound structure:

1. Create hidden `Schemail` marker:
   ```racket
   (gmail-create-label "Schemail" #:label-list-visibility "labelHide")
   ```

2. For existing `Schemail/Newsletter` labels:
   - Extract base name: `Newsletter`
   - Create flat label: `Newsletter`
   - Apply both `Newsletter` and `Schemail` to emails
   - Remove old `Schemail/Newsletter` label

3. Update code to use flat labels:
   - Remove `Schemail/` prefix logic
   - Apply marker label alongside content label

---

## Code Changes Required

### llm-classifier.rkt

**Before:**
```racket
(define full-label (string-append "Schemail/" (string-titlecase label)))
```

**After:**
```racket
(define full-label (string-titlecase label))  ; flat label
(define schemail-marker-id (gmail-find-or-create-label "Schemail" #:hidden #t))
```

### llm.rkt (tool calling)

**Before:**
```racket
(define label-name
  (string-append "Schemail/" (string-titlecase raw-label-name)))
```

**After:**
```racket
(define label-name (string-titlecase raw-label-name))  ; flat label
;; Also apply Schemail marker
```

### CLI Query

**Already correct:**
```racket
(define gmail-query "in:inbox -label:Schemail")
```

This works regardless of label structure because we always apply `Schemail` marker.
