# Interactive TUI Email Processor

## Vision

A keyboard-driven TUI (Terminal User Interface) for processing inbox emails with AI assistance. Think Superhuman's workflow but in the terminal, integrated with schemail.

**Goal:** Churn through inbox efficiently with Do/Defer/Delegate actions, AI-drafted replies, and send-and-archive in one flow.

## User Experience

### Main Flow

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Inbox Zero Assistant                    [42 unprocessed emails] ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Email 1/42

From: alice@example.com
To: you@example.com
Date: 2026-02-16 14:32
Subject: Quick question about the proposal

┌────────────────────────────────────────────────────────────────┐
│ Hey Peter,                                                     │
│                                                                │
│ Can you take a look at the attached proposal and let me know  │
│ your thoughts? I need feedback by EOD tomorrow.                │
│                                                                │
│ Thanks!                                                        │
│ Alice                                                          │
└────────────────────────────────────────────────────────────────┘

AI Classification: Personal (human conversation requiring response)

┌────────────────────────────────────────────────────────────────┐
│ Actions                                                        │
├────────────────────────────────────────────────────────────────┤
│ [R] Reply now (AI draft)     [D] Defer (keep in inbox)       │
│ [A] Archive only             [L] Label + Archive              │
│ [F] Forward                  [S] Skip                         │
│ [Q] Quit                     [?] Help                         │
└────────────────────────────────────────────────────────────────┘

Action: _
```

### Reply Flow (Press 'R')

```
Generating reply with Claude...

┌────────────────────────────────────────────────────────────────┐
│ Draft Reply                                                    │
├────────────────────────────────────────────────────────────────┤
│ Hi Alice,                                                      │
│                                                                │
│ I'll review the proposal and get back to you this afternoon.  │
│                                                                │
│ Best,                                                          │
│ Peter                                                          │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ [E] Edit   [S] Send & Archive   [K] Keep in Inbox   [C] Cancel│
└────────────────────────────────────────────────────────────────┘

Action: _
```

### Edit Mode (Press 'E')

```
┌────────────────────────────────────────────────────────────────┐
│ Edit Reply (Ctrl+S to save, Esc to cancel)                    │
├────────────────────────────────────────────────────────────────┤
│ Hi Alice,                                                      │
│                                                                │
│ I'll review the proposal and get back to you this afternoon.▊ │
│                                                                │
│ Best,                                                          │
│ Peter                                                          │
│                                                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘

Lines: 6  Chars: 89
```

### Success Confirmation

```
✓ Sent reply to alice@example.com
✓ Archived email
✓ Applied label: Personal

[41 emails remaining]

Loading next email...
```

## Features

### Core Features

1. **Keyboard-driven workflow** - No mouse needed
2. **AI classification** - Reuses schemail classifier
3. **AI reply drafting** - Context-aware responses
4. **Send & Archive** - One action to reply and clean up
5. **Label application** - Automatic categorization
6. **Progress tracking** - See how many emails left

### Actions

| Key | Action | Description |
|-----|--------|-------------|
| `R` | Reply | Draft AI reply, edit, send & archive |
| `D` | Defer | Keep in inbox, apply label, move to next |
| `A` | Archive | Archive without label, move to next |
| `L` | Label | Choose label manually, archive, move to next |
| `F` | Forward | Forward to someone else, archive |
| `S` | Skip | Move to next without any action |
| `U` | Undo | Undo last action |
| `Q` | Quit | Save progress and exit |
| `?` | Help | Show keyboard shortcuts |

### Smart Features

1. **Context-aware replies**
   - Analyzes email content and thread history
   - Matches tone (formal/casual)
   - Includes relevant context from previous emails

2. **Quick snippets**
   - `Ctrl+1` - "Thanks! Will review and get back to you"
   - `Ctrl+2` - "Thanks for reaching out. Not interested at this time."
   - `Ctrl+3` - "Can you send more details?"
   - Customizable in config

3. **Batch operations**
   - Mark multiple emails for same action
   - Bulk archive all automated emails
   - Bulk label all similar emails

4. **Smart suggestions**
   - "Looks like a receipt - archive?"
   - "Similar to 3 other recruiting emails - archive all?"
   - "No reply needed - archive only?"

## Architecture

### Tech Stack

**Option A: Pure Racket**
- `raart` - ASCII art and terminal rendering
- `termbox` - Terminal control (if available)
- Native Racket for everything

**Option B: Racket + Python TUI**
- Racket backend (Gmail API, LLM, logic)
- Python `textual` frontend (nicer TUI)
- IPC via JSON over stdin/stdout

**Option C: Racket + Web UI**
- Racket backend with web server
- React/Svelte frontend in browser
- More familiar UI toolkit
- Could be mobile-friendly

**Recommendation: Option A** (pure Racket, start simple)

### Code Structure

```
bin/
  schemail-tui              # New TUI entry point

src/
  tui/
    app.rkt                 # Main TUI app loop
    screens.rkt             # Screen rendering
    keyboard.rkt            # Keyboard input handling
    email-view.rkt          # Email display widget
    reply-editor.rkt        # Reply composition widget
    
  email-sender.rkt          # Gmail send API (NEW)
  reply-drafter.rkt         # AI reply generation (NEW)
  
  # Reuse existing:
  gmail.rkt                 # Gmail API wrapper
  oauth.rkt                 # OAuth2 flow
  llm-classifier.rkt        # Classification
  label-utils.rkt           # Label operations
```

### Gmail Send API

Need to add sending capability:

```racket
;; src/email-sender.rkt

(define (gmail-send-email #:to to
                         #:subject subject
                         #:body body
                         #:in-reply-to [in-reply-to #f]
                         #:thread-id [thread-id #f])
  ;; Build RFC 2822 message
  ;; Base64url encode
  ;; POST to /gmail/v1/users/me/messages/send
  ...)

(define (gmail-create-draft #:to to
                           #:subject subject
                           #:body body)
  ;; POST to /gmail/v1/users/me/drafts
  ...)
```

### Reply Drafting Prompt

```racket
;; src/reply-drafter.rkt

(define reply-drafter-prompt
  "You are an email reply assistant. Draft a professional, concise email reply.

CONTEXT:
- Your name: {user_name}
- Your email: {user_email}

ORIGINAL EMAIL:
From: {from}
Subject: {subject}
Date: {date}

{body}

INSTRUCTIONS:
1. Draft a clear, professional reply
2. Match the tone of the original (formal/casual)
3. Be concise (2-4 sentences usually)
4. Sign with user's name only (no title/company unless original was very formal)
5. Address all questions/requests in the original

Output ONLY the reply body, no subject line.")
```

### Main TUI Loop

```racket
;; src/tui/app.rkt

(define (run-tui)
  ;; Initialize
  (define messages (fetch-unprocessed-emails))
  (define current-index 0)
  (define undo-stack '())
  
  ;; Main loop
  (let loop ()
    (when (< current-index (length messages))
      (define msg (list-ref messages current-index))
      
      ;; Render screen
      (clear-screen)
      (display-email msg current-index (length messages))
      (display-actions)
      
      ;; Get user input
      (define action (read-key))
      
      ;; Handle action
      (match action
        [#\r (handle-reply msg)]
        [#\d (handle-defer msg)]
        [#\a (handle-archive msg)]
        [#\l (handle-label msg)]
        [#\s (handle-skip)]
        [#\q (exit 0)]
        [_ (void)])
      
      ;; Move to next
      (set! current-index (add1 current-index))
      (loop)))
  
  ;; Done
  (display-completion-screen))

(define (handle-reply msg)
  ;; 1. Classify email to get label
  (define classification (classify-email msg))
  
  ;; 2. Generate AI reply
  (display "Generating reply...")
  (define draft (draft-reply msg))
  
  ;; 3. Show draft, get user choice
  (display-draft draft)
  (define choice (read-key))
  
  (match choice
    [#\e (edit-draft draft)]    ; Edit in $EDITOR
    [#\s (send-and-archive msg draft classification)]
    [#\k (send-keep-inbox msg draft)]
    [#\c (void)]                ; Cancel
    [_ (void)]))

(define (send-and-archive msg draft classification)
  ;; 1. Send reply
  (gmail-send-email 
    #:to (message-from msg)
    #:subject (format "Re: ~a" (message-subject msg))
    #:body draft
    #:in-reply-to (message-id msg)
    #:thread-id (message-thread-id msg))
  
  ;; 2. Apply label + Schemail marker
  (apply-labels msg (list (:label classification) "Schemail"))
  
  ;; 3. Archive original
  (gmail-archive msg)
  
  ;; 4. Show confirmation
  (display "✓ Sent and archived"))
```

## User Configuration

```racket
;; config/tui.rkt

;; User info for reply drafting
(define user-name "Your Name")
(define user-email "you@example.com")

;; Reply snippets (Ctrl+N)
(define reply-snippets
  (hash 1 "Thanks! Will review and get back to you."
        2 "Thanks for reaching out. Not interested at this time."
        3 "Can you send more details?"
        4 "Will do, thanks for the reminder."
        5 "Sounds good, let's set up a time to chat."))

;; Signature
(define signature "Best,\nPeter")

;; Auto-archive patterns (skip TUI for obvious emails)
(define auto-archive-patterns
  '("noreply@"
    "no-reply@"
    "donotreply@"
    "notifications@github.com"))

;; Default model for drafting
(define draft-model "claude-haiku-4-5")  ; Fast and cheap

;; Use Sonnet for important senders
(define draft-model-vip "claude-sonnet-4-5")
(define vip-senders
  '("boss@company.com"
    "important@client.com"))
```

## Command Line Interface

```bash
# Basic usage
bin/schemail-tui

# Process specific query
bin/schemail-tui --query "label:Newsletters"

# Use Sonnet for all replies (expensive but high quality)
bin/schemail-tui --model sonnet-4-5

# Start from specific message
bin/schemail-tui --start 10

# Batch size (how many to load at once)
bin/schemail-tui --batch 50

# Help
bin/schemail-tui --help
```

## Implementation Plan

### Phase 1: Basic TUI (MVP)

**Goal:** Display emails, navigate, archive

1. [ ] Basic TUI framework (screen rendering, keyboard input)
2. [ ] Display single email with formatting
3. [ ] Navigation (next/previous)
4. [ ] Archive action
5. [ ] Quit and progress tracking

**Estimated time:** 4-6 hours

### Phase 2: AI Classification

**Goal:** Auto-classify and show suggestions

1. [ ] Integrate with existing classifier
2. [ ] Display AI classification result
3. [ ] Apply label + archive action
4. [ ] Defer action (label + keep inbox)

**Estimated time:** 2-3 hours

### Phase 3: Reply Drafting

**Goal:** AI-drafted replies with editing

1. [ ] Add Gmail send API support
2. [ ] Create reply drafting prompt
3. [ ] Generate AI reply
4. [ ] Show draft to user
5. [ ] Send & archive action

**Estimated time:** 4-5 hours

### Phase 4: Reply Editing

**Goal:** Edit drafts before sending

1. [ ] Open draft in $EDITOR (vim/emacs/nano)
2. [ ] Or: Built-in simple text editor
3. [ ] Save edits back
4. [ ] Send edited reply

**Estimated time:** 3-4 hours

### Phase 5: Polish

**Goal:** Nice-to-have features

1. [ ] Undo stack
2. [ ] Reply snippets (Ctrl+N)
3. [ ] Batch operations
4. [ ] Smart suggestions
5. [ ] Progress bar
6. [ ] Help screen (?)
7. [ ] Color coding
8. [ ] Thread view (show previous emails in thread)

**Estimated time:** 6-8 hours

**Total estimated time:** 20-30 hours for full-featured version

### Phase 0: Proof of Concept (Start Here)

**Goal:** Validate the concept with minimal code

1. [ ] Display one email in terminal (no fancy TUI)
2. [ ] Read keyboard input (R/A/S/Q)
3. [ ] Generate one AI reply with Haiku
4. [ ] Print it to terminal
5. [ ] Ask: send? (y/n)
6. [ ] Actually send via Gmail API

**Estimated time:** 2-3 hours

If this feels good, proceed to Phase 1.

## Cost Analysis

### Haiku-based (Recommended)

- Classification: ~$0.0006/email
- Reply drafting: ~$0.0008/email (slightly longer prompts)
- **Total: ~$0.0014/email**

**Scenarios:**
- 50 emails with replies: $0.07
- 200 emails with replies: $0.28
- 1000 emails: ~$1.40

### Sonnet-based (High Quality)

- Classification: ~$0.10/email
- Reply drafting: ~$0.12/email
- **Total: ~$0.22/email**

**Scenarios:**
- 50 emails: $11
- 200 emails: $44

**Recommendation:** Use Haiku for most emails, Sonnet for VIPs (configurable).

## Alternatives / Prior Art

### Similar Tools

1. **Superhuman** - $30/month, web-based, AI features, keyboard-driven
2. **Shortwave** - AI email client, similar features
3. **mutt** - Classic TUI email client (no AI)
4. **neomutt** - Modern fork of mutt (no AI)
5. **aerc** - Modern TUI email client (no AI)

### What Makes This Different

- **Free** (just API costs)
- **AI-native** (classification + drafting built-in)
- **Inbox Zero workflow** (opinionated, focused)
- **Self-hosted** (your data, your control)
- **Integrates with schemail** (same labels, same classification)

## Open Questions

1. **Editor choice:** Built-in text widget vs $EDITOR vs both?
   - Built-in: More integrated, simpler
   - $EDITOR: More powerful, familiar to power users
   - Both: Best of both worlds, more code

2. **Threading:** Show full thread context or just latest email?
   - Latest only: Simpler, faster
   - Full thread: Better context, more scrolling

3. **Attachments:** How to handle?
   - Ignore in TUI, mention "has attachments"
   - Open in external viewer (xdg-open)
   - Download to temp dir

4. **HTML emails:** How to display?
   - Convert to plain text (w3m, lynx, html2text)
   - Show raw HTML (ugly)
   - Skip in TUI, open in browser

5. **Offline mode:** Cache emails locally?
   - Always fetch fresh (simpler, always up-to-date)
   - Cache for offline (more complex, stale data risk)

## Next Steps

1. **Get user feedback:** Is this worth building?
2. **Build POC:** 2-3 hour prototype to validate concept
3. **User testing:** Does the workflow feel good?
4. **Iterate:** Based on feedback
5. **Polish:** Add nice-to-have features

## References

- [raart](https://docs.racket-lang.org/raart/index.html) - Racket ASCII art library
- [textual](https://textual.textualize.io/) - Python TUI framework (if going hybrid)
- [Gmail API - Send](https://developers.google.com/gmail/api/guides/sending)
- [mutt](http://www.mutt.org/) - For UX inspiration
- [Superhuman](https://superhuman.com/) - For workflow inspiration

---

**Status:** Proposal / Idea Stage

**Estimated effort:** 20-30 hours for MVP → full-featured version

**Next action:** Build 2-3 hour POC to validate concept
