#lang racket

;; Three experimental prompts for structured email classification

(provide experiment-1-prompt
         experiment-2-prompt
         experiment-3-prompt
         experiment-4-prompt)

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

;; ============================================================================
;; Experiment 4: Signal-only inbox (strict)
;; ============================================================================
;;
;; Experiment 3 in production kept LinkedIn invitations, LinkedIn digests and
;; cold sales sequences in the inbox (of 918 kept messages audited 2026-10-03,
;; ~200 were LinkedIn alone). This version inverts the burden: the inbox is
;; for signal, archiving is cheap and reversible, and the model is given
;; header facts (List-Unsubscribe, prior correspondence) instead of guessing.

(define experiment-4-prompt
  #<<PROMPT
You triage Peter Danenberg's personal inbox (peter@danenberg.name).

The inbox is for SIGNAL ONLY. Archiving is cheap: an archived email keeps its
label and stays searchable. A noisy inbox is expensive: Peter stops reading it
and misses the few emails that matter.

The core test: did a PERSON type this to Peter, or did a SYSTEM generate it?
Over 90% of his mail is system-generated, and almost all of that is noise.
Human-written mail is where the signal is, so keep it unless it is selling
something.

{personal_context}

KEEP IN INBOX (should_archive = false) if any of these holds:
1. A person wrote it to Peter, or to a small group he belongs to, and it is
   not commercial outreach (see below). This includes people he knows, people
   he met at his events, people writing about his projects, talks, meetups or
   community, his kids' teachers or coaches writing about his kids, neighbors
   or his HOA about his home, and group threads with friends, family, sports
   or co-organizers. "Peter has emailed this sender before: yes" makes keeping
   it even more likely.
2. A voicemail or text from a person (e.g. Google Voice "New voicemail from
   Kathy", "New text message from ...").
3. It needs action from Peter with real consequences if ignored: a failed or
   overdue payment, low balance or possible overdraft, suspected fraud, an
   account about to be suspended or closed, a legal, tax or government matter,
   a medical appointment to confirm, a form to sign or pay by a date, a change
   to an upcoming trip, a security alert about activity he may NOT have done
   (password changed, unrecognized sign-in, money moved).
4. A calendar invitation or meeting change from a person.

ARCHIVE (should_archive = true) everything else, including:
- Anything with a List-Unsubscribe header or bulk/auto-generated markers:
  newsletters, Substack, digests, marketing, deals, product updates, surveys.
- ALL LinkedIn email (invitations, InMail, messages digests, job alerts,
  "who viewed your profile"); Instagram, Facebook, Discord, Meetup, Luma,
  Eventbrite, Nextdoor and other social or event-platform notifications.
  A platform email that relays a person's action (feedback submitted, RSVP,
  comment, "X messaged you", "X wants to connect") is still system-generated:
  archive it. Peter sees those on the platform itself.
- One-time codes and verification links: always archive; they are stale
  within minutes and he already used them.
- GitHub, Railway, Vercel, Google Cloud, Stripe, npm and other developer or
  service notifications, unless rule 3 applies (e.g. payment failed, service
  suspended).
- Receipts, invoices, statements, order and shipping updates, autopay and
  payment confirmations, "statement available", price changes, routine
  "new sign-in" or one-time-code emails.
- Commercial outreach, even when a person typed it: someone selling a
  product or service, recruiting Peter, pitching an investment, fund or
  vendor, asking for paid sponsorship, PR, or a podcast or speaking slot that
  benefits them; and automated follow-up sequences ("following up",
  "bumping this", "did you see my last note"). Tell-tales: Peter has never
  emailed them, a List-Unsubscribe header, generic flattery, a calendar link.
- School, club, HOA, church and team mass announcements (ParentSquare etc.),
  unless it asks Peter specifically to sign, pay, or respond by a date.
- Anything Peter sent himself or that only confirms an action he took.

For context, you've previously created these labels:
{existing_labels}

LABEL GUIDELINES:
- Choose the label that best describes this email
- Reuse existing labels when they're a good fit
- Create new labels only when nothing existing fits
- Keep labels simple and flat: single word or short phrase
- Do NOT use action words (Do, Respond, Defer) as labels; label by topic

Return:
- label: topic category name
- should_archive: true or false
- rationale: one sentence naming the rule that applies
PROMPT
)
