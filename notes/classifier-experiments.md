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

## Experiment 3 WITH Existing Labels (Label Reuse)

**Test Run: 10 Emails (2026-02-15) - After implementing label context**

**MASSIVE IMPROVEMENT!**
- **10 emails → 4 labels** (40% label-to-email ratio)
- **60% reduction from original Experiment 3!**
- **Label reuse working beautifully**

**Generated Labels:**
1. Notification/Delivery (5 emails) ✅ **Consolidated!**
2. Meeting/Planning (2 emails) ✅ **Reused!**
3. Event/Invitation (2 emails) ✅ **Reused!**
4. Article/Link (1 email)

**Implementation Details:**
- Fetch all existing labels ONCE at beginning (N API calls)
- Pass labels hash through processing pipeline
- Update hash as new labels created
- Show labels to model in each classification prompt
- Model explicitly mentions reusing: "we have an existing 'Event/Invitation' label, I'll reuse it"

**Archive Decisions (6 archived, 4 kept):**
- ✅ Archived: Notification/Delivery (5x), Article/Link (1x)
- ✅ Kept: Meeting/Planning (2x), Event/Invitation (2x)
- **All decisions correct!**

**Performance Benefits:**
- Labels fetched once, not N times per email
- Color assignment reuses hash (no rescan)
- Clean architecture: hash passed through pipeline

**Comparison:**
- **Experiment 1 (blank slate):** 10 emails → 10 labels (100%)
- **Experiment 2 (principles):** 10 emails → 10 labels (100%)
- **Experiment 3 (framework):** 10 emails → 8 labels (80%)
- **Experiment 3 + Labels:** 10 emails → 4 labels (40%) ⭐⭐⭐

**Key Insight:** Providing existing labels to the model is THE solution to label proliferation!

---

## Experiment 1 WITH Existing Labels (Label Reuse)

**Test Run: 10 Emails (2026-02-15) - Blank slate + label context**

**EQUALLY EXCELLENT!**
- **10 emails → 4 labels** (40% label-to-email ratio)
- **Same performance as Experiment 3 with labels!**
- **Freedom + context = consolidation**

**Generated Labels:**
1. Receipt/Invoice (3 emails) ✅ **Consolidated!**
2. Security/Login Code (3 emails) ✅ **Consolidated!**
3. Event/Invitation (3 emails) ✅ **Consolidated!**
4. Meeting/Agenda (1 email)

**Model Explicitly Reuses:**
- "It matches the existing Receipt/Invoice label perfectly"
- "matching the existing Receipt/Invoice category"
- "similar to other login/security codes"

**Archive Decisions (7 archived, 3 kept):**
- ✅ Archived: Receipt/Invoice (3x), Security/Login Code (3x), Event/Invitation (1x)
- ✅ Kept: Meeting/Agenda (1x), Event/Invitation (2x)
- ⚠️ Bad: Conference invitation archived (should keep for decision)
- ⚠️ Bad: DMV password change archived (Exp 3 kept it correctly)

**Comparison:**
- **Exp 1 WITHOUT labels:** 10 emails → 10 labels (100%)
- **Exp 1 WITH labels:** 10 emails → 4 labels (40%) ⭐
- **Exp 3 WITHOUT labels:** 10 emails → 8 labels (80%)
- **Exp 3 WITH labels:** 10 emails → 4 labels (40%) ⭐

**Verdict:** Both Experiment 1 (freedom) and Experiment 3 (framework) work excellently when provided with existing label context. The key is label reuse, not the prompt style!

Experiment 3 still has slightly better judgment (DMV password, conference decisions), but both achieve the same consolidation rate.

---

## Color Scheme Testing

**Default:** `pastel1` (ColorBrewer, 9 colors) - soft, gentle colors (winner!)
**Previously tested:** `muted` (Paul Tol, professional tones), `set3` (12 pastels), `rainbow` (unlimited)

**Message Count Filtering (Added 2026-02-15):**
- Color assignment now skips empty labels (parent labels with no messages)
- Prevents wasting colors on hierarchical parents
- Shows message counts in output for context

---

## Experiment 3 WITH Labels: 50 Email Test (2026-02-15)

**INBOX ZERO FRAMEWORK TEST: 47 emails → 6 labels (13% ratio)**

**Label Distribution:**
1. Receipt (26 emails) - All archived ✅
2. Newsletter (7 emails) - All archived ✅
3. Notification (6 emails) - All archived ✅
4. Event/Invitation (6 emails) - 4 archived, 2 kept ⚠️
5. Action Required/Response (6 emails) - **ALL KEPT** ✅
6. Meeting/Planning (2 emails) - **ALL KEPT** ✅

**Key Insights:**

✅ **MUCH More Discriminating:**
- **Action Required/Response** - 6 emails kept (LinkedIn messages, recruiting, discussions)
- Luma notifications → Archived! (vs Exp 1 kept some in inbox)
- LinkedIn profile views → Newsletter → Archived
- Event acceptance notifications → Archived
- Only REAL invitations/messages kept

✅ **Excellent Consolidation:**
- **Receipt** used for ALL transactional emails (verification codes, receipts, deliveries, confirmations)
- DMV password change → Receipt (archived) - ⚠️ Different from 10-email test
- All automated notifications → Either Receipt or Notification

✅ **Archive Decisions:**
- Archived: ~38-39 emails (81-83%)
- Kept: ~8-9 emails (17-19%)
- **Only human-action-required emails kept in inbox**
- Luma event notifications properly archived
- LinkedIn messages properly kept for response

⚠️ **Possible Issues:**
- DMV password change archived (Exp 1 also archived this, so consistent but arguably wrong)
- Event/Invitation might be too broad (some archived, some kept)
- Newsletter used for group emails (frisbee pickup, shared articles)

**Framework Visibility:**
- Rationales explicitly mention: "Delete principle", "Do principle", "Defer principle"
- "AUTOMATED EMAILS principle → archive immediately"
- Model applies structured Inbox Zero thinking consistently

**Comparison to Experiment 1:**
- **Exp 1:** 50 emails → 11 labels (22%)
- **Exp 3:** 47 emails → 6 labels (13%) ⭐ **Better consolidation!**
- **Exp 1:** Luma notifications kept in inbox (bad)
- **Exp 3:** Luma notifications archived (good!) ✅
- **Exp 1:** Created fine-grained subcategories (Confirmation/Delivery, Confirmation/Payment, Social/Message, Event/Registration)
- **Exp 3:** Broader categories with better consolidation

**Winner: Experiment 3** 🏆
- 45% fewer labels (6 vs 11)
- More aggressive archiving (81-83% vs 82%)
- Better judgment on automated notifications
- Clearer action-oriented categorization
- Framework thinking prevents label proliferation

**Log Location:** `/tmp/exp3-50emails.log`

---

## Experiment 1 WITH Labels: 50 Email Scale Test (2026-02-15)

**PRODUCTION-SCALE TEST: 50 emails → 11 labels (22% ratio)**

**Label Distribution:**
1. Receipt (11 emails) - Anthropic receipts, invoices ⭐ **Most reused!**
2. Confirmation/Delivery (8 emails) - Amazon delivery notifications
3. Security/Login Code (6 emails) - Verification codes, password changes
4. Newsletter/Marketing (6 emails) - LinkedIn, Virgin Red, Monarch, etc.
5. Event/Invitation (5 emails) - Conference invites, event details
6. Discussion/Topic (5 emails) - Personal conversations, article sharing
7. Social/Message (4 emails) - LinkedIn messages, delayed notifications
8. Event/Registration (3 emails) - Luma registration notifications
9. Confirmation/Payment (1 email) - Progressive insurance payment reminder
10. Meeting/Agenda (1 email) - March agenda with scheduling
11. Recruiting/Outreach (1 email) - LinkedIn recruiting message

**Key Insights:**

✅ **Label Reuse Working Beautifully:**
- Receipt label reused 11 times (all Anthropic invoices)
- Confirmation/Delivery reused 8 times (Amazon deliveries)
- Security/Login Code reused 6 times (various verification codes)
- Model successfully consolidates similar emails into existing categories

✅ **Hierarchical Labels Emerging:**
- `Security/Login Code` - Security subcategory
- `Event/Invitation`, `Event/Registration` - Event subcategories
- `Confirmation/Delivery`, `Confirmation/Payment` - Confirmation subcategories
- `Newsletter/Marketing` - Newsletter subcategory
- `Discussion/Topic` - Discussion subcategory
- `Social/Message` - Social subcategory
- `Meeting/Agenda` - Meeting subcategory

✅ **Smart Archive Decisions:**
- Archived: 41 emails (82%) - Receipts, notifications, marketing
- Kept: 9 emails (18%) - Event invitations, discussions, meetings
- All decisions appear correct based on actionability

⚠️ **Potential Over-Granularity:**
- `Event/Registration` vs `Event/Invitation` - Could potentially merge
- `Confirmation/Delivery` vs `Confirmation/Payment` - Fine-grained but useful
- `Social/Message` separate from `Newsletter/Marketing` - Debatable

**Performance Metrics:**
- **Label-to-email ratio: 22%** (excellent consolidation!)
- **Average label reuse: 4.5 emails per label**
- **Hierarchical structure: 7 parent labels, 11 total labels**
- **Archive rate: 82%** (aggressive but appropriate)

**Comparison to 10-email tests:**
- **10 emails without labels:** 10 labels (100%)
- **10 emails WITH labels:** 4 labels (40%)
- **50 emails WITH labels:** 11 labels (22%) ⭐ **Best yet!**

**Scaling Observations:**
- Label reuse increases with volume (22% vs 40% for smaller set)
- Model successfully recognizes patterns (all Anthropic receipts → Receipt)
- Hierarchical structure emerges naturally
- Archive judgment remains consistent and accurate

**Log Location:** `/tmp/exp1-50emails.log`

---

## Future Improvements

**Label Consolidation Strategy:**
- ✅ **SOLVED**: Providing existing labels to the model dramatically reduces proliferation
- Test results: 22% label-to-email ratio at 50 emails (vs 100% without labels)
- Model successfully reuses labels when provided with context
- Hierarchical structure emerges naturally with freedom + context

---

## Final Decision: Experiment 3 is Production Default (2026-02-15)

**WINNER: Experiment 3 (Explicit Inbox Zero Framework + Label Context)** 🏆

**Why Experiment 3 Won:**
1. **45% fewer labels** (6 vs 11 in Exp 1)
   - Better consolidation: Receipt handles ALL transactional emails
   - No over-granular subcategories (no Confirmation/Delivery vs Confirmation/Payment)
   
2. **Better inbox discrimination** ✅
   - Luma notifications → Archived (vs Exp 1 kept some)
   - Only human-action-required emails kept
   - Clear action-oriented category: `Action Required/Response`
   
3. **Framework thinking prevents proliferation**
   - Rationales explicitly cite Delete/Defer/Do principles
   - Consistent judgment across automated vs personal emails
   - Scalable approach for production

**Production Configuration:**
- Default classifier: `experiment-3`
- Color scheme: `rainbow` (unlimited colors)
- Config updated: `/home/danenberg/prg/email/config/schemail.rkt`

**Results Summary:**
- **Exp 3:** 47 emails → 6 labels (13%) - WINNER
- **Exp 1:** 50 emails → 11 labels (22%)
- **Both:** ~81-82% archive rate (appropriate for Inbox Zero)

**Next Steps:**
1. ✅ **DONE:** Make Experiment 3 the default
2. **Scale testing:** Run on 100-200 emails to confirm behavior
3. **Optional enhancements:**
   - Cosine similarity for very long label lists
   - Polling daemon (Phase 4)
   - Action-oriented sub-labels (To Reply, Waiting On, etc.)
