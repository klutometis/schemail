#lang racket

;; Three experimental prompts for structured email classification

(provide experiment-1-prompt
         experiment-2-prompt
         experiment-3-prompt)

;; ============================================================================
;; Experiment 1: Blank Slate - See What Model Comes Up With
;; ============================================================================

(define experiment-1-prompt
  #<<PROMPT
Classify this email with a label and decide if it should be archived.

Archive means remove from inbox. Most emails should be archived.
Only keep in inbox if it requires human attention, decision, or response.

For context, you've previously created these labels:
{existing_labels}

LABEL GUIDELINES:
- Choose the label that best describes this email
- Reuse existing labels when they're a good fit
- Create new labels when needed for clarity
- Keep labels simple and flat: single word or short phrase

Return:
- label: a short category name
- should_archive: true or false
- rationale: brief explanation
PROMPT
)

;; ============================================================================
;; Experiment 2: Inbox Zero Principles (High-Level)
;; ============================================================================

(define experiment-2-prompt
  #<<PROMPT
You are my email assistant following Inbox Zero principles.

Classify each email with a label and decide whether to archive it.

Inbox Zero means: inbox is for things requiring action, not storage.
Archive anything that doesn't need a response, decision, or follow-up.

For context, you've previously created these labels:
{existing_labels}

LABEL GUIDELINES:
- Choose the label that best describes this email
- Reuse existing labels when they're a good fit
- Create new labels when needed for clarity
- Keep labels simple and flat: single word or short phrase

Return:
- label: a short category name
- should_archive: true or false
- rationale: brief explanation

Default: archive=true unless human action is needed.
PROMPT
)

;; ============================================================================
;; Experiment 3: Inbox Zero Principles (Explicit)
;; ============================================================================

(define experiment-3-prompt
  #<<PROMPT
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

For context, you've previously created these labels:
{existing_labels}

LABEL GUIDELINES:
- Choose the label that best describes this email
- Reuse existing labels when they're a good fit
- Create new labels when needed for clarity
- Keep labels simple and flat: single word or short phrase

Return:
- label: category name
- should_archive: true or false  
- rationale: which principle applies

Default: archive unless Defer or Do applies.
PROMPT
)
