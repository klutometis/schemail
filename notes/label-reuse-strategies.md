# Label Reuse Strategies

## The Problem

When we provide existing labels to the model, we create "gravitational force" - the model is biased toward reusing established labels even when they're not quite right.

**Observed behavior:**
- LinkedIn notifications → "Personal" (because Personal exists and is vaguely related)
- Family Tree DNA announcements → "Personal" (automated but looks legitimate)
- Model errs toward reuse over accuracy

**Result:** Labels become "junk drawers" that lose semantic meaning.

## Three Approaches to Label Reuse

### Approach 1: Aggressive Reuse (Original)

**Prompt style:**
```racket
EXISTING LABELS (prefer reusing over creating new):
{existing_labels}

LABEL GUIDELINES:
- PREFER reusing existing labels when they fit
- Only create new labels when existing ones don't match well
```

**Characteristics:**
- Very pushy about reuse
- Multiple directives: "prefer reusing", "PREFER", "(prefer...)"
- Creates strong gravitational pull

**Results:**
- ✅ Excellent consolidation (271 emails → 5 labels, 1.8% ratio)
- ✅ Prevents label proliferation
- ❌ Quality suffers - labels become catch-alls
- ❌ Personal becomes junk drawer for anything vaguely human-related

**When to use:**
- When label count is the #1 priority
- When you're okay with manual curation later
- Initial processing of large volumes

---

### Approach 2: Balanced (Recommended)

**Prompt style:**
```racket
For context, you've previously created these labels:
{existing_labels}

Choose the label that best describes this email. Reuse when appropriate, 
create new when needed. Keep labels simple and flat.
```

**Characteristics:**
- Labels presented as "context" not directive
- Equal weight to accuracy and reuse
- "Best describes" prioritizes correctness
- Soft permission to create new labels

**Expected results:**
- ✅ Better accuracy (LinkedIn → Newsletters, not Personal)
- ✅ More semantic clarity
- ⚠️ Slightly more labels (maybe 7-10 instead of 5)
- ✅ Each label has clearer meaning

**When to use:**
- Default for production
- When label quality matters
- When you want semantic clarity over minimal count

---

### Approach 3: Free Choice (Experimental)

**Prompt style:**
```racket
EXISTING LABELS:
{existing_labels}

Create labels that accurately describe the email.
Keep labels simple and flat: single word or short phrase.
```

**Characteristics:**
- Labels shown purely for information
- No explicit reuse directive
- Emphasis on accuracy only
- Model decides freely

**Expected results:**
- ✅ Maximum accuracy
- ✅ Labels perfectly match email semantics
- ❌ Potential label proliferation (15-20+ labels?)
- ❌ May recreate near-duplicates (Notification vs Notifications)

**When to use:**
- Exploratory testing
- When you want to see natural categorization
- When you plan to manually consolidate later
- Small batches for evaluation

---

## Comparison Table

| Metric | Aggressive | Balanced | Free Choice |
|--------|-----------|----------|-------------|
| **Label count** | Very low (5) | Medium (7-10) | High (15-20+) |
| **Accuracy** | Poor | Good | Excellent |
| **Semantic clarity** | Low | High | Very high |
| **Manual curation needed** | High | Low | Medium |
| **Label proliferation risk** | None | Low | High |

---

## Real-World Example

**Email:** LinkedIn notification about profile views

### Approach 1 (Aggressive):
```
Existing labels: Personal (42 messages), Events (168), ...
Model thinks: "Personal is for people-related things, close enough"
Result: Label = Personal ❌
```

### Approach 2 (Balanced):
```
For context: Personal (42 messages), Events (168), ...
Model thinks: "This is automated from LinkedIn, not a personal message. 
              I should create 'Newsletters' or 'Notifications'"
Result: Label = Newsletters ✅
```

### Approach 3 (Free):
```
Existing labels: [shown but not emphasized]
Model thinks: "Automated notification from social platform"
Result: Label = Social Notifications ⚠️ (accurate but specific)
```

---

## Migration Path

If you're on Approach 1 and want to move to Approach 2:

1. **Update prompt** to balanced style
2. **Don't clean labels** - keep existing ones
3. **Reprocess new emails** - model will see old labels but not be forced to use them
4. **Watch for new labels** - LinkedIn might create Newsletters, etc.
5. **Manually consolidate** if too many emerge

**Key insight:** You don't need to reprocess everything. Just update the prompt and let new emails flow. Over time, better labels will emerge and you can manually migrate old emails if needed.

---

## Recommendations by Use Case

### Personal Use (100-1000 emails/day)
**Use:** Approach 2 (Balanced)
- Quality matters more than count
- 7-10 labels is totally manageable
- Clearer semantics = better search/triage

### Enterprise/High Volume (10k+ emails/day)
**Use:** Approach 1 (Aggressive) → Approach 2
- Start aggressive to get initial consolidation
- Move to balanced once you have stable categories
- Manual curation as needed

### Research/Experimentation
**Use:** Approach 3 (Free Choice)
- See what categories naturally emerge
- Learn from model's choices
- Manually consolidate insights into Approach 2

---

## Current Status (2026-02-15)

**Active approach:** Approach 1 (Aggressive reuse)

**Results:** 271 emails → 5 labels
- Travel (11)
- Events (168)
- Personal (42) ← **Becoming junk drawer**
- Jobs (20)
- Receipts (30)

**Problem identified:** Personal contains:
- Real human conversations ✅
- LinkedIn automated notifications ❌
- Family Tree DNA announcements ❌
- Other automated "legitimate" emails ❌

**Next action:** Migrate to Approach 2 (Balanced) to improve Personal label quality.

---

## Implementation

All three approaches use the same code - just different prompt wording in `config/classifier-prompts.rkt`:

```racket
;; Update the {existing_labels} section in each experiment prompt
(define experiment-3-prompt
  #<<PROMPT
...
[INSERT APPROACH HERE]
...
PROMPT
)
```

No code changes needed, just prompt engineering.
