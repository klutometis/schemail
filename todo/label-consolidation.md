# Label Consolidation Strategy

## Problem

All three classifier experiments show high label proliferation:
- **Experiment 1:** 10 emails → 10 labels (100%)
- **Experiment 2:** 10 emails → 10 labels (100%)  
- **Experiment 3:** 10 emails → 8 labels (80%) - Best, but still granular

**Examples of over-specificity:**
- `Event Notification - Invite Accepted` (could be `Event/Notification`)
- `Dmv Mdl Confirmation` (could be `Confirmation`)
- `Event Details Request` vs `Action Required Event Details` (redundant concepts)

## Proposed Solution: Feed Existing Labels to Model

### Implementation Plan

1. **Query existing labels before classification**
   - Use `gmail-list-labels` + filter to user labels with messages
   - Include all labels (will optimize later if needed)
   - Format: label name + message count

2. **Add to prompt**
   ```
   EXISTING LABELS (reuse when appropriate):
   - Receipt (5 messages)
   - Meeting Planning (3 messages)
   - Event Notification (2 messages)
   - Conference Invitation (1 message)
   ...
   
   Instructions:
   - PREFER reusing existing labels over creating new ones
   - Only create new labels when existing ones don't fit well
   - Use hierarchical labels (Category/Subcategory) for specificity
   ```

3. **Hierarchical label guidance**
   Add explicit encouragement:
   "For specific subcategories, use hierarchical labels like Event/Notification, Event/Invitation"

### Benefits

- ✅ Natural consolidation as label corpus grows
- ✅ Model sees patterns across previous classifications
- ✅ Encourages consistency without being prescriptive
- ✅ Respects "freedom and LLMs" philosophy

### Future Optimizations

**If label list gets too long (100+ labels):**
- Limit to top N by message count
- Use cosine similarity to cluster/dedupe similar labels
- Filter by recency (labels used in last 30 days)
- Semantic search: only include labels similar to current email

**Possible approaches:**
- Embed label names using sentence transformers
- Calculate cosine similarity between label embeddings
- Show only labels above similarity threshold
- Or: cluster labels and show cluster representatives

## Implementation Tasks

- [ ] Add `get-labels-with-counts` function to label-utils.rkt
- [ ] Update all 3 experiment prompts to include existing labels section
- [ ] Add hierarchical label guidance to prompts
- [ ] Test on same 10-email batch to compare results
- [ ] Document new label proliferation metrics

## Open Questions

- **Which base experiment?** Experiment 1 (freedom) or Experiment 3 (framework)?
  - Leaning toward Experiment 3 for 20% consolidation win
  - But Experiment 1's freedom is appealing
  - Could test both with existing labels added

- **Pre-seeded Inbox Zero categories?**
  - Hard no for now (fights model creativity)
  - Revisit if consolidation approach doesn't work

## Success Metrics

**Goal:** Reduce label-to-email ratio from 80-100% to 50-60%

**How to measure:**
- Run on same 10-email test set
- Track: unique labels created, labels reused, avg emails per label
- Compare across experiments with/without existing labels
