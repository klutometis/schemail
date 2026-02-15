# Flat Label Experiment Results (2026-02-15)

## Prompt Change: Nudge Toward Flat Labels

**Modified all three experiment prompts to:**
- Remove hierarchical examples (Event/Invitation, Action Required/Response)
- Add gentle nudge: "Keep labels simple and flat: single word or short phrase"
- No explicit examples (let model discover spontaneously)
- No negative prompting (avoid "don't use...")

**Goal:** See what the model naturally creates without hierarchical guidance.

---

## Experiment 3 WITH Flat Nudge: 50 Emails

**RESULT: 50 emails → 4 labels (8% ratio!)**

### Label Distribution

1. **Events (31 emails)** - 19 kept in inbox, 12 archived
   - Real invitations kept (conference, hackathon, choir visit)
   - Luma notifications archived ✅
   - RSVP acceptances archived ✅
   
2. **Personal (8 emails)** - 7 kept, 1 archived
   - LinkedIn messages from real people
   - Email discussions
   - Meeting coordination
   
3. **Travel (6 emails)** - All archived
   - Virgin Atlantic codes & welcome emails
   - Grouped by domain (Virgin = Travel)
   
4. **Jobs (5 emails)** - All kept in inbox
   - Recruiting messages
   - Job opportunities
   - Investment opportunities
   - LinkedIn connection invitations

### Archive Breakdown
- **Archived:** 31 emails (62%)
- **Kept in inbox:** 19 emails (38%)

---

## Key Findings

### ✅ Model Spontaneously Created Flat Labels!

No hierarchical labels created. The model naturally generated:
- `Travel` (not Travel/Flights or Travel/Loyalty)
- `Events` (not Event/Invitation)
- `Personal` (not Personal/Discussion)
- `Jobs` (not Jobs/Recruiting)

**The gentle nudge worked!** No negative prompting needed.

### ✅ Semantic Grouping Still Works

Model intelligently grouped related content:
- Virgin Atlantic emails → Travel
- Luma notifications → Events (archived)
- Real event invitations → Events (kept)
- LinkedIn recruiting → Jobs

### ✅ Better Inbox Discrimination

Compared to nested version:
- Luma notifications properly archived ✅
- Real invitations kept for decision
- Action-oriented distinction clear
- Only 4 labels total (vs 6 nested)

### ⚠️ Events Label Broad

Events has 31 emails - covers both:
- Real invitations requiring decision (kept)
- Automated notifications (archived)

Could potentially split into:
- `Invitations` (keep for RSVP)
- `Events` (archive notifications)

But model seems to handle archive/keep distinction well within single label.

---

## Comparison: Nested vs Flat

| Metric | Nested (Previous) | Flat (This Run) |
|--------|------------------|----------------|
| **Total Labels** | 6 labels + 3 empty parents = 9 | **4 labels (44% fewer!)** |
| **Archived** | ~38/47 (81%) | 31/50 (62%) |
| **Kept in Inbox** | ~9/47 (19%) | 19/50 (38%) |
| **Empty Parents** | 3 (wasted) | **0 (none!)** |
| **Luma Handling** | Archived ✅ | Archived ✅ |

### Key Differences

**Nested version had:**
- Receipt (26) - Transactional stuff
- Newsletter (7) - Marketing
- Notification (7) - Platform alerts
- Event/Invitation (6)
- Action Required/Response (6)
- Meeting/Planning (2)

**Flat version has:**
- Events (31) - Combined invitations + notifications
- Personal (8) - Human conversations
- Travel (6) - Travel-related
- Jobs (5) - Career/opportunities

**Flat version is MORE AGGRESSIVE at archiving:**
- Receipt, Newsletter, Notification → all archived in nested
- Travel, Events (notifications) → archived in flat
- But LESS aggressive overall: 62% vs 81% archive rate

**Why less archived overall?**
- Events label kept more emails (19 kept vs nested version's split)
- Model being more conservative with "Events" vs fine-grained nested categories

---

## Spontaneous Label Creativity

Model chose interesting semantic categories:
- **Travel** - Not "Loyalty Programs" or "Airlines"
- **Events** - Simple, clear
- **Personal** - Human communication
- **Jobs** - Career-related

No over-specific labels like:
- ❌ "DMV Mdl Confirmation"
- ❌ "Confirmation/Delivery"
- ❌ "Event/Registration"
- ❌ "Action Required/Response"

**The model naturally prefers simplicity when nudged!**

---

## Inbox Zero Comparison

**Inbox Zero's 10 labels:**
- To Reply, Awaiting Reply, FYI, Actioned, Newsletter, Marketing, Calendar, Receipt, Notification, Cold Email

**Our flat 4 labels:**
- Events, Personal, Travel, Jobs

**Mapping:**
- Our "Personal" ≈ their "To Reply"
- Our "Events" ≈ their "Calendar"
- Our "Jobs" ≈ their "Cold Email" (recruiting)
- **Missing:** Awaiting Reply, FYI, Actioned, Newsletter, Marketing, Receipt, Notification

**Observation:**
- Model created domain-based labels (Events, Jobs, Travel)
- Inbox Zero uses action-based labels (To Reply, Actioned)
- Model didn't create transactional categories (Receipt, Newsletter) this time
- Possible because test emails were more event/conversation heavy?

---

## Recommendations

### Option A: Keep Flat 4-Label System
**Pros:**
- Extremely simple (4 labels!)
- 0 empty parents
- Model handles archive/keep well within broad categories
- Scales well - room to add more as needed

**Cons:**
- Events label too broad (31 emails)
- No explicit transactional categories (Receipt, Newsletter)
- Less action-oriented than Inbox Zero

### Option B: Add Transactional Labels
Keep flat but add:
- Receipt
- Newsletter
- Notification

**Result:** ~7 flat labels (matches Inbox Zero's count)

**Pros:**
- Better coverage of email types
- Clearer semantic separation
- Handles automated emails better

**Cons:**
- More labels (but still reasonable at 7)

### Option C: Action-Oriented Evolution
Teach model Inbox Zero-style labels:
- To Reply
- Awaiting Reply
- Actioned
- Events
- Newsletter
- Receipt

**Pros:**
- Clear workflow (Reply → Actioned → Archive)
- Action-first instead of domain-first
- Proven approach

**Cons:**
- Requires prompt redesign
- More complex categorization
- Need to test on 50+ emails

---

## Next Steps

1. **Run on 200 emails** to see if more labels emerge naturally
2. **Test on diverse email types** (more transactional emails?)
3. **Consider seeding with examples** if current labels too broad
4. **Optional:** Test action-oriented prompt (Inbox Zero style)

**Current verdict:** Flat labels work beautifully! 4 labels with intelligent grouping and good archive discrimination.

**Log location:** `/tmp/exp3-flat-50emails.log`
