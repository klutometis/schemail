# Quickstart Guide

## What Is This?

An intelligent email filtering system built in Racket that uses **Claude AI** to automatically classify and organize your Gmail inbox. Instead of writing dozens of specific rules, you give Claude high-level instructions and it decides what to do with each email.

## What We've Built So Far

✅ **Gmail OAuth Integration** - Secure access to your Gmail  
✅ **Filter DSL** - S-expression based filter language  
✅ **LLM Integration** - Claude Sonnet 4.5 with tool calling  
✅ **Agentic Processing** - AI decides actions autonomously  
✅ **Dry-Run Mode** - Test safely before making changes  
✅ **Test Suite** - Comprehensive testing tools  

## Quick Test

### Using the CLI (Recommended)

```bash
# Process last 10 emails (dry-run, safe)
schemail process --last 10

# Process with hybrid strategy (fast rules + LLM)
schemail process --last 20 --filter hybrid

# Actually execute (make real changes!)
schemail process --last 5 --execute
```

### Using the Test Suite

```bash
cd /home/danenberg/prg/email
racket src/test-llm.rkt
# Choose option 1: "Dry-run on recent emails"
```

The system will:
1. Fetch recent emails
2. Send each to Claude with your preferences
3. Show what actions Claude would take (but not execute them)

## How It Works

### Label Structure

**Flat labels + hidden marker:**
- Content labels: `Receipt`, `Newsletter`, `Shipping` (visible, colorful)
- Hidden marker: `Schemail` (marks as processed, hidden from sidebar)
- Both applied together automatically

**Example classifications:**
- Receipt from Anthropic → `Receipt` + `Schemail` (archived)
- Newsletter from NYTimes → `Newsletter` + `Schemail` (archived)
- Shipping from Amazon → `Shipping` + `Schemail` (archived)
- Email from human → `Action` + `Schemail` (stays in inbox)

### High-Level Instructions

Instead of writing rules like:
```scheme
(filter (from "noreply@linkedin.com") (label "notification") (archive))
(filter (from "notifications@github.com") (label "notification") (archive))
;; ... 50 more rules
```

You write:
```scheme
(filter (always)
        (llm-agent "You're my email assistant. Handle emails intelligently..."))
```

Claude figures out the rest!

## Test Results

**First test: 5/5 emails classified correctly** ✅

- Amazon shipping notification → notification (archived, read)
- Anthropic receipts (3x) → notification (archived, read)
- GoDaddy order confirmation → notification (archived, read)

**Cost:** ~$0.007 per email (~$20/month for 100 emails/day)

## Project Structure

```
/home/danenberg/prg/email/
├── src/
│   ├── oauth.rkt          # Gmail OAuth flow
│   ├── gmail.rkt          # Gmail API wrapper
│   ├── filters.rkt        # Filter DSL
│   ├── llm.rkt            # Claude integration
│   └── test-llm.rkt       # Test suite
├── config/
│   ├── credentials.json   # OAuth credentials
│   ├── preferences.rkt    # Email handling instructions
│   └── filters.rkt        # Filter configurations
├── notes/
│   └── agentic.md         # Implementation details & test results
├── TODO.md                # Development roadmap
├── README.md              # Original design doc
└── QUICKSTART.md          # This file
```

## Configuration Files

### `config/preferences.rkt` - Your Email Assistant's Instructions

```racket
"You are my personal email assistant. Process each email according to these rules:

1. 'action' - Real humans writing specifically to me. Leave in inbox.
2. 'notification' - Automated messages. Archive and mark read.
3. 'recruiter' - Job opportunities. Archive.

If unsure, leave in inbox. Better safe than sorry."
```

### `config/filters.rkt` - Filter Strategies

Three strategies available:

**1. Pure Agentic** (LLM does everything)
```scheme
(filter (always)
        (llm-agent email-assistant-prompt))
```

**2. Hybrid** (Fast rules + LLM fallback) ← **Recommended**
```scheme
;; Fast pattern matching for obvious cases
(filter (from "noreply@github.com") (label "github") (archive) (skip))

;; LLM handles the rest
(filter (always) (llm-agent email-assistant-prompt))
```

**3. Selective LLM** (Only for ambiguous cases)
```scheme
(filter (from "noreply@") (label "notification") (archive) (skip))
(filter (not (has-label "notification"))
        (llm-agent email-assistant-prompt))
```

## CLI Usage

### Process Emails

```bash
# Dry-run on last 10 emails (default, safe)
schemail process --last 10

# Process last 50 with hybrid strategy
schemail process --last 50 --filter hybrid

# Actually execute actions (LIVE MODE)
schemail process --last 10 --execute

# Process only unread emails
schemail process --unread --execute

# Process emails from a date range
schemail process --since "2026-02-01" --until "2026-02-14"

# Interactive mode (review each email)
schemail process --last 20 --interactive

# Custom Gmail query
schemail process --query "from:linkedin.com" --execute
```

### Run as Daemon

```bash
# Check for new emails every 5 minutes
schemail daemon --interval 5

# Daemon with custom query
schemail daemon --interval 3 --query "is:unread -from:spam"
```

### Testing Modes (Alternative)

```bash
# Run full test suite
schemail test

# Or use the interactive test tool:
racket src/test-llm.rkt
```

## What's Next?

Current status: **Phase 3 Complete** (LLM Integration working!)

Next up:
1. Build polling daemon to automatically process new emails
2. Add more sophisticated filtering strategies
3. Implement caching to reduce API costs
4. Add web UI for monitoring

## Cost Breakdown

**Model:** Claude Sonnet 4.5
- ~$0.007 per email
- ~$0.67 per 100 emails
- ~$20 per month (100 emails/day)

**Alternative:** Claude Haiku 4.5 (cheaper, slightly less smart)
- ~$0.002 per email
- ~$6 per month (100 emails/day)

To switch models, edit `src/llm.rkt`:
```racket
(define CLAUDE-MODEL "claude-3-5-haiku-20241022")  ; Use Haiku instead
```

## Documentation

- **`notes/agentic.md`** - Complete implementation details, architecture, test results
- **`TODO.md`** - Development roadmap and progress tracking
- **`README.md`** - Original design discussion and rationale
- **`NOTES.md`** - Three LLM approaches (structured JSON, tool calling, hybrid)

## Key Concepts

**Agentic Processing:** Instead of "if this then that" rules, you give the LLM high-level goals and it decides what to do. More flexible, handles edge cases you didn't anticipate.

**Tool Calling:** Claude has access to 5 "tools":
- `apply_label(name)` - Label an email
- `archive_email()` - Archive it
- `star_email()` - Star it
- `mark_as_read()` - Mark as read
- `do_nothing(reason)` - Leave it alone

**Dry-Run Mode:** Test everything safely before making real changes.

**Hybrid Filtering:** Use fast pattern matching for obvious cases, LLM for complex ones. Best of both worlds.

## Need Help?

1. Check `notes/agentic.md` for detailed implementation docs
2. Check `TODO.md` to see what's implemented
3. Run tests to see it in action
4. Review `config/preferences.rkt` to understand the prompt

## Philosophy

**From the README:**
> "The config-representation would be in the same language as the implementation"

This is the core Lisp insight. Your filters are code, your code is data. The system is elegant because configuration and implementation speak the same language.

**On LLMs:**
We chose the **agentic approach** (tool calling) over strict rules because:
- More flexible (handles edge cases)
- More maintainable (one prompt vs. 50 rules)
- More intelligent (LLM understands context)
- More fun (watching Claude make decisions is cool!)

---

**Status:** Working! Tested! Ready for Phase 4 (daemon)! 🚀
