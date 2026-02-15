# Classifier Experiments Log

Documenting observations from testing different classifier prompt experiments.

## Experiment 1: Blank Slate (Maximally Permissive)

**Prompt Philosophy:** Minimal guidance - let the model decide what categories make sense with minimal constraints.

### Test Run: 10 Emails (2026-02-15)

**Label Proliferation:**
- **10 emails → 10 unique labels** (100% label-to-email ratio)
- This suggests potential label explosion with minimal guidance
- Each email got its own highly specific category

**Generated Labels:**
1. Event Inquiry
2. Receipt (2 emails)
3. Conference Invitation
4. Meeting Request Incomplete
5. Verification Code
6. Security Alert
7. Product Pitch Discussion
8. Marketing/Newsletter (hierarchical)
9. Linkedin Notification

**Observations:**
- ✅ **Archiving accuracy seems spot-on** (6/10 archived appropriately)
- ⚠️ **High label granularity** - might become unmanageable at scale
- ✅ **Smart hierarchical categorization** (`Marketing/Newsletter`)
- ✅ **Contextual awareness** (detected incomplete message, expired verification code)
- ⚠️ **Empty parent labels** created automatically by Gmail (e.g., `Marketing` with 0 messages)

**Archive Decisions (6 archived, 4 kept):**
- ✅ Archived: Receipt (2x), Verification Code (expired), Product Pitch Discussion, Marketing/Newsletter, Linkedin Notification
- ✅ Kept: Event Inquiry, Conference Invitation, Meeting Request Incomplete, Security Alert

**Accuracy Assessment:**
- Archive decisions: **100% correct** - all archived items were informational/non-actionable
- Inbox retention: **100% correct** - all kept items require human attention/response
- Security awareness: **Excellent** - DMV password change correctly flagged as needing verification

**Label Normalization Working:**
- `verification_code` → `Verification Code` ✅
- `product_pitch_discussion` → `Product Pitch Discussion` ✅
- `linkedin_notification` → `Linkedin Notification` ✅
- `Marketing/Newsletter` → Created parent + child correctly ✅

### Implications

**Pros:**
- Model makes intelligent, context-aware decisions
- No need to predefine categories
- Naturally discovers useful patterns (e.g., receipts, verification codes)
- Excellent at judging actionability

**Cons:**
- Could lead to hundreds of labels with large email volumes
- May need consolidation/merging over time
- Parent labels created unnecessarily (waste colors without message count filtering)

**Questions for Experiments 2 & 3:**
- Will explicit Inbox Zero principles reduce label proliferation?
- Can we get similar accuracy with fewer, broader categories?
- Is high granularity actually a problem, or does it provide better organization?

---

## Experiment 2: Inbox Zero Principles

**Prompt Philosophy:** High-level Inbox Zero guidance without explicit framework.

### Test Run: 10 Emails (2026-02-15)

**Label Proliferation:**
- **10 emails → 10 unique labels** (100% label-to-email ratio, same as Experiment 1)
- High-level guidance did NOT reduce label granularity
- Still creates hyper-specific labels for individual cases

**Generated Labels:**
1. Receipt
2. Meeting Planning
3. Event Coordination
4. Conference Invitation
5. Meeting Coordination
6. Security Alert
7. Dmv Mdl Confirmation ⚠️ (hyper-specific)
8. Payment Confirmation
9. Verification Code
10. Marketing

**Fine-Grained Label Examples:**
- `Dmv Mdl Confirmation` - Single-purpose label for DMV mobile license
- `Payment Confirmation` - Could potentially consolidate with other confirmations
- Model doesn't naturally consolidate similar categories

**Archive Decisions (6 archived, 4 kept):**
- ✅ Archived: Receipt, DMV mDL Confirmation, Payment Confirmation, Verification Code, Marketing
- ⚠️ Questionable: Security Alert (DMV password change) - Exp1 kept this (better decision)
- ✅ Kept: Meeting Planning, Event Coordination, Conference Invitation, Meeting Coordination

**Comparison to Experiment 1:**
- **Same label count** (10 labels for 10 emails)
- More generic/action-oriented naming (`Meeting Coordination` vs `Meeting Request Incomplete`)
- **Worse decision:** Archived password change notification (should verify)
- Still no natural consolidation of similar categories

**Observations:**
- ⚠️ High-level principles alone don't reduce label proliferation
- ⚠️ Model makes one arguably worse decision (password change archiving)
- ✅ Slightly more action-oriented label names
- ⚠️ No evidence of learning to reuse or consolidate categories

---

## Experiment 3: Explicit Inbox Zero Framework

**Prompt Philosophy:** Explicit delete/delegate/respond/defer/do framework.

### Test Run: 10 Emails (2026-02-15)

**Label Proliferation:**
- **10 emails → 8 labels** (80% label-to-email ratio)
- ✅ **FIRST EXPERIMENT TO SHOW CONSOLIDATION!** (20% reduction)
- Model successfully reused labels for similar emails

**Generated Labels:**
1. Meeting Planning (1 email)
2. Event Details Request (1 email)
3. Conference Invitation (1 email)
4. Action Required Event Details (1 email)
5. Linkedin Notification (2 emails) ✅ **Consolidated!**
6. Event Registration Notification (2 emails) ✅ **Consolidated!**
7. Event Notification Invite Accepted (1 email)
8. Delivery Notification (1 email)

**Label Consolidation Success:**
- ✅ Two LinkedIn notifications → Single `Linkedin Notification` label
- ✅ Two event registration emails → Single `Event Registration Notification` label
- Framework thinking helped model recognize similar categories

**Archive Decisions (6 archived, 4 kept):**
- ✅ Archived: LinkedIn Notification (2x), Event Registration (2x), Event Notification, Delivery Notification
- ✅ Kept: Meeting Planning, Event Details Request, Conference Invitation, Action Required Event Details
- **All decisions look correct!**

**Framework Visibility:**
- Rationales mention explicit framework concepts: "Defer/Do principle", "Do principle"
- Model applies structured thinking to categorization
- Better judgment of actionability

**Remaining Over-Specificity:**
- `Event Notification Invite Accepted` vs `Event Registration Notification` - Could consolidate
- `Event Details Request` vs `Action Required Event Details` - Similar concepts
- Still room for improvement but much better than Experiments 1 & 2

**Comparison to Experiments 1 & 2:**
- **Experiment 1:** 10 labels (100% proliferation)
- **Experiment 2:** 10 labels (100% proliferation)
- **Experiment 3:** 8 labels (80% - **20% reduction!**) ⭐

**Winner!** Experiment 3 shows the explicit framework helps the model:
1. Recognize similar email types and reuse labels
2. Make better archive/keep decisions
3. Apply structured thinking to categorization

---

## Color Scheme Testing

**Default:** `pastel1` (ColorBrewer, 9 colors) - soft, gentle colors (winner!)
**Previously tested:** `muted` (Paul Tol, professional tones), `set3` (12 pastels), `rainbow` (unlimited)

**Message Count Filtering (Added 2026-02-15):**
- Color assignment now skips empty labels (parent labels with no messages)
- Prevents wasting colors on hierarchical parents
- Shows message counts in output for context

## Future Improvements

**Label Consolidation Strategy:**
- Current issue: Both Experiment 1 and 2 create highly granular labels (10 emails → 10 labels)
- Examples of over-specificity: `Dmv Mdl Confirmation`, `Payment Confirmation` (could be generic `Confirmation`)
- Potential solution: Feed list of existing labels to classifier with instruction to reuse when appropriate
- Benefits: Better organization, fewer colors needed, easier to navigate
- Test after Experiment 3
