# Structured Classifier Approach

## Motivation

Moving away from tool calling to a simpler structured output classifier.

### Problems with Current Tool Calling Approach

1. **Too prescriptive** - We're forcing the model to archive by auto-archiving on label application
2. **Too many tools** - Model has star_email, mark_as_read, archive, etc. - too much to think about
3. **Loss of autonomy** - System overrides model decisions (auto-archive)

### Proposed: Structured Output Classifier

Instead of giving the model tools, ask it to classify with structured output:

```json
{
  "label": "receipt",           // What category is this?
  "should_archive": true,       // Should this leave the inbox?
  "rationale": "Automated receipt from Anthropic API usage"
}
```

**Key insight:** Archive is binary decision, default is TRUE (most emails should be archived).
Only keep in inbox for exceptional cases requiring human attention.

---

## Three Experiments

### Experiment 1: Blank Slate - See What Model Comes Up With

**Prompt:**
```
Classify this email with a label and decide if it should be archived.

Archive means remove from inbox. Most emails should be archived.
Only keep in inbox if it requires human attention, decision, or response.

Return:
- label: a short category name
- should_archive: true or false
- rationale: brief explanation
```

**Goal:** See what labeling scheme the model naturally creates without constraints.

**Questions:**
- What labels does it invent?
- Does it properly distinguish archive vs. keep?
- Is the rationale helpful?

---

### Experiment 2: Inbox Zero Principles (High-Level)

**Prompt:**
```
You are my email assistant following Inbox Zero principles.

Classify each email with a label and decide whether to archive it.

Inbox Zero means: inbox is for things requiring action, not storage.
Archive anything that doesn't need a response, decision, or follow-up.

Return:
- label: a short category name  
- should_archive: true or false
- rationale: brief explanation

Default: archive=true unless human action is needed.
```

**Goal:** See if invoking "Inbox Zero" as a concept influences behavior.

**Questions:**
- Does it archive more aggressively?
- Does it better distinguish "action needed" vs "FYI"?
- What labeling scheme emerges?

---

### Experiment 3: Inbox Zero Principles (Explicit)

Based on `notes/inbox-zero.txt` - derive explicit principles:

**Inbox Zero Philosophy:**
1. **Delete** - Obvious junk/spam → archive immediately
2. **Delegate** - Not for you, forward/delegate → archive after delegating
3. **Respond** - Quick response (< 2 min) → archive after response
4. **Defer** - Needs time/thought → keep in inbox, maybe label for later
5. **Do** - Requires action → keep in inbox until done

**Prompt:**
```
You are my email assistant. Classify each email using Inbox Zero principles.

PRINCIPLES:
- Delete: Junk, spam, irrelevant → archive immediately
- Respond: Can reply quickly (< 2 min) → archive (I'll respond later)
- Defer: Needs time/thought → keep in inbox, label for context
- Do: Requires action/decision → keep in inbox
- Delegate: Not for me → archive

AUTOMATED EMAILS (receipts, notifications, alerts):
→ Archive (no human action needed)

PERSONAL EMAILS (real people writing to me):
→ Keep in inbox by default (may need response)

Return:
- label: category name
- should_archive: true or false  
- rationale: which principle applies

Default: archive unless Defer or Do applies.
```

**Goal:** Most explicit guidance - see if it improves decision quality.

**Questions:**
- Better archive decisions?
- More consistent labeling?
- Does explicit framework help or hinder?

---

## Implementation Plan

### 1. Create New Classifier Module

**File:** `src/llm-classifier.rkt`

```racket
;; Structured output classifier (no tool calling)
(define classifier-schema
  #hash((type . "object")
        (properties . #hash((label . #hash((type . "string")
                                            (description . "Short category name")))
                             (should_archive . #hash((type . "boolean")
                                                     (description . "Remove from inbox?")))
                             (rationale . #hash((type . "string")
                                                (description . "Brief explanation")))))
        (required . ("label" "should_archive" "rationale"))))

(define (classify-email message prompt)
  ;; Call Claude with structured output
  ;; Return: (values label should-archive? rationale)
  ...)
```

### 2. Update Filter DSL

Add new action: `(llm-classify prompt)`

```scheme
;; Instead of:
(filter (always) (llm-agent preferences))

;; Use:
(filter (always) (llm-classify prompt))
```

### 3. Apply Classification Results

```racket
(define (apply-classification message label should-archive? rationale)
  (displayln (format "Label: ~a" label))
  (displayln (format "Archive: ~a" should-archive?))
  (displayln (format "Rationale: ~a" rationale))
  
  ;; Apply Schemail/ prefix
  (define full-label (string-append "Schemail/" (string-titlecase label)))
  
  ;; Create and apply label
  (ensure-label-exists full-label)
  (gmail-modify-message message-id #:add-labels (list label-id))
  
  ;; Archive if model says so
  (when should-archive?
    (gmail-modify-message message-id #:remove-labels '("INBOX"))))
```

### 4. Three Test Configurations

**File:** `config/classifier-prompts.rkt`

```racket
(provide experiment-1-prompt
         experiment-2-prompt  
         experiment-3-prompt)

(define experiment-1-prompt
  "Classify this email...") ;; Blank slate

(define experiment-2-prompt
  "...Inbox Zero principles...") ;; High-level

(define experiment-3-prompt
  "...PRINCIPLES: Delete, Respond...") ;; Explicit
```

### 5. CLI Commands

```bash
# Test each experiment
./bin/schemail process --last 50 --classifier experiment-1 --skip-processed
./bin/schemail process --last 50 --classifier experiment-2 --skip-processed
./bin/schemail process --last 50 --classifier experiment-3 --skip-processed

# Compare results
./bin/schemail analyze experiments
```

---

## Expected Outcomes

### Experiment 1: Blank Slate
- **Labels:** Probably invents: receipts, notifications, personal, work, etc.
- **Archive rate:** 60-70% (conservative without guidance)
- **Label diversity:** High (creative, inconsistent)

### Experiment 2: Inbox Zero Principles
- **Labels:** More action-oriented: to-respond, to-read, archived, etc.
- **Archive rate:** 70-80% (more aggressive with principle)
- **Label diversity:** Medium (guided but flexible)

### Experiment 3: Explicit Principles
- **Labels:** Aligned with principles: delete, respond, defer, do, delegate
- **Archive rate:** 80-90% (explicit guidance to archive by default)
- **Label diversity:** Low (constrained by framework)

---

## Success Metrics

For each experiment, measure:

1. **Archive accuracy** - Did it correctly identify what needs human attention?
2. **Label consistency** - Does it use consistent labels for similar emails?
3. **Label utility** - Are the labels actually helpful for finding things later?
4. **False negatives** - Important emails incorrectly archived
5. **False positives** - Junk emails left in inbox

**Golden rule:** Zero tolerance for false negatives (missing important email).

---

## Comparison: Tool Calling vs Structured Classifier

| Aspect | Tool Calling (Current) | Structured Classifier (Proposed) |
|--------|----------------------|--------------------------------|
| **Flexibility** | High - model decides multiple actions | Medium - binary decision |
| **Simplicity** | Low - 5 tools, complex execution | High - simple classification |
| **Control** | Low - we override (auto-archive) | High - model decides, we respect |
| **Token cost** | Higher (tool definitions) | Lower (simpler schema) |
| **Predictability** | Low - can call any tools | High - always same structure |
| **Observability** | Medium - see tool calls | High - explicit rationale |

**Verdict:** Structured classifier is simpler, cheaper, more respectful of model decisions.

---

## Notes from Discussion

1. **Don't force archive** - Current system auto-archives on label, removing model autonomy
2. **Trust the model** - Let it decide archive vs. keep
3. **Archive is default** - Most emails should be archived, only keep exceptional ones
4. **Labels should be emergent** - Don't prescribe label scheme, see what model creates
5. **Rationale is key** - Helps debug model decisions and build trust

---

## Next Steps

1. Implement `src/llm-classifier.rkt` with structured output
2. Create three experiment prompts in `config/classifier-prompts.rkt`
3. Add `--classifier` flag to CLI
4. Run all three experiments on same 50 emails
5. Compare results, pick best approach
6. Iterate on prompt based on results

---

## Open Questions

1. Should label be freeform or constrained to suggestions?
2. Should we log all classifications for analysis?
3. How to handle emails that are both notification AND action?
4. Should rationale be shown to user or just logged?
5. What to do with emails model is uncertain about?

---

## Future: Learning from Corrections

Once we have classifications with rationale, we could:

1. Track when user moves archived email back to inbox (false negative)
2. Track when user archives email that was kept (false positive)
3. Use these corrections to refine prompts
4. Build a feedback loop for continuous improvement

But that's phase 2. First: implement classifier, run experiments, see what works.
