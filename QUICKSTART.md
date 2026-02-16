# Schemail Quickstart Guide

## What Is This?

An intelligent email filtering system built in Racket that uses **Claude AI** (Haiku 4.5 or Sonnet 4.5) to automatically classify and organize your Gmail inbox using Inbox Zero principles.

**Default model:** Haiku 4.5 (~$0.0006/email, 166x cheaper than Sonnet)

## Current Status

**✅ Production Ready!**

- Structured classifier with three tested experiments
- Flat label structure (no nested hierarchy)
- Label reuse to prevent proliferation
- Automatic rainbow color coding
- Tested at scale: 50 emails → 4 labels, excellent discrimination

## Quick Start

### 1. Setup (First Time Only)

#### Install Racket Dependencies

```bash
raco pkg install simple-oauth2 http-easy
```

#### Get Gmail OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use existing)
3. Enable Gmail API
4. Create OAuth 2.0 credentials (Desktop app)
5. Download `credentials.json` to `config/` directory

#### Get Anthropic API Key

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Create API key
3. Export: `export ANTHROPIC_API_KEY=your_key_here`

### 2. Test on 10 Emails (Safe Dry-Run)

**Easy way:**
```bash
bin/classify
```

**Manual way:**
```bash
bin/schemail process --last 10 --classifier experiment-3 --model haiku-4-5
```

This will:
- Fetch last 10 unprocessed emails from inbox
- Show what Claude would do (label + archive decisions)
- Use cheap Haiku model (~$0.006 total cost)
- NOT make any changes (dry-run mode)

### 3. Process 50 Emails (Live)

**Easy way:**
```bash
bin/classify 50 --live
```

**Manual way:**
```bash
bin/schemail process --last 50 --classifier experiment-3 --model haiku-4-5 --execute
```

This will:
- Actually apply labels
- Archive non-actionable emails
- Apply rainbow colors
- Skip already-processed emails (those with `Schemail` label)
- Use cheap Haiku model (~$0.03 total cost)
- Auto-log to `/tmp/schemail-classify-*.log`

### 4. View Results in Gmail

Your emails are now labeled and colored! Check your Gmail to see:
- Flat labels: `Events`, `Personal`, `Travel`, `Jobs`, etc.
- Rainbow colors applied automatically
- Only action-required emails in inbox
- Everything else archived with labels

## Understanding the Classifier

### Three Experiments

Schemail includes three classifier experiments:

1. **Experiment 1** - Blank slate with minimal guidance
2. **Experiment 2** - High-level Inbox Zero principles
3. **Experiment 3** - Explicit Inbox Zero framework ⭐ **Recommended**

**Use Experiment 3** - it's tested, performs best, and uses explicit Delete/Delegate/Respond/Defer/Do principles.

### What Experiment 3 Does

**Automated emails → Archive:**
- Receipts, confirmations, notifications
- Marketing newsletters
- One-time passcodes
- Event registration notifications

**Personal emails → Keep in inbox:**
- Real people writing to you
- Event invitations requiring RSVP
- Job opportunities requiring decision
- Anything needing human action

**Result:** Clean inbox with only actionable emails!

### Flat Label Structure

Model spontaneously creates simple labels:
- `Events` - Invitations, meetings, conferences
- `Personal` - Human conversations, discussions
- `Travel` - Airlines, loyalty programs
- `Jobs` - Recruiting, opportunities
- `Receipt` - Transactions (when present in test set)
- `Newsletter` - Marketing (when present in test set)

**Why flat?**
- No nested hierarchy (no `Event/Invitation`)
- No empty parent labels wasting space
- Simpler UI, easier to understand
- Model consolidates intelligently

## Common Commands

### Process Emails

**Using wrapper script (recommended):**

```bash
# Test on 10 emails (dry-run, Haiku)
bin/classify

# Test on 50 emails (dry-run, Haiku)
bin/classify 50

# Process 50 emails (live, Haiku - cheap!)
bin/classify 50 --live

# Process 200 emails (live, auto-logged, Haiku)
bin/classify 200 --live
```

**Using CLI directly (full control):**

```bash
# Test on 10 emails (dry-run, Haiku)
bin/schemail process --last 10 --classifier experiment-3 --model haiku-4-5

# Process today's emails (last 24 hours, no count limit)
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute

# Process last 2 days (no count limit, auto-pagination)
bin/schemail process --last-days 2 --classifier experiment-3 --model haiku-4-5 --execute

# Process ALL unprocessed emails (auto-pagination for 70k+ emails)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Run as daemon (polls every 5 minutes for new emails)
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5

# Process 50 emails with Sonnet (expensive but higher quality)
bin/schemail process --last 50 --classifier experiment-3 --model sonnet-4-5 --execute

# Process only unread
bin/schemail process --unread --classifier experiment-3 --model haiku-4-5 --execute

# Process date range
bin/schemail process --since "2026-02-01" --classifier experiment-3 --model haiku-4-5 --execute

# Process with custom query
bin/schemail process --query "label:INBOX" --last 100 --classifier experiment-3 --model haiku-4-5 --execute
```

### Label Management

```bash
# Apply colors to all labels
bin/schemail labels assign-colors

# Apply specific color scheme
bin/schemail labels assign-colors --color-scheme rainbow

# Clean up all experiment labels (reprocess from scratch)
bin/schemail labels cleanup
```

### Help

```bash
bin/schemail help
```

## Configuration

### Main Config: `config/schemail.rkt`

```racket
;; Default classifier (experiment-3 recommended)
(define default-classifier 'experiment-3)

;; Color scheme (rainbow = unlimited colors)
(define color-scheme 'rainbow)

;; Labels to exclude from coloring
(define exclude-from-coloring '("Groups" "Saved"))
```

### Classifier Prompts: `config/classifier-prompts.rkt`

Three prompts available. Experiment 3 is most mature:

```racket
;; Experiment 3: Explicit Inbox Zero framework
;; - Delete: Junk, spam → archive
;; - Respond: Quick reply → archive after sending
;; - Defer: Needs thought → keep in inbox
;; - Do: Requires action → keep in inbox
;; - Delegate: Not for you → forward and archive
```

## How It Works

### Label System

**Two labels applied per email:**
1. **Content label** (visible) - e.g., `Events`, `Personal`
2. **Schemail marker** (hidden) - Marks as processed

**Query for unprocessed emails:**
```
in:inbox -label:Schemail
```

This means:
- First run: Process all inbox emails
- Subsequent runs: Only new emails (no Schemail label)
- Can reprocess by removing Schemail label

### Processing Flow

```
1. Fetch unprocessed emails from inbox
   ↓
2. Fetch existing labels once (hash table)
   ↓
3. For each email:
   - Provide existing labels to Claude
   - Claude returns: label, should_archive, rationale
   - Normalize label name (titlecase, spaces)
   - Create label if needed
   - Apply content label + Schemail marker
   - Archive if should_archive = true
   - Update labels hash (for next email)
   ↓
4. Apply rainbow colors to all labels
```

**Key optimization:** Labels fetched once, reused throughout processing.

### Label Reuse (The Secret Sauce)

Claude sees existing labels and their message counts:
```
Existing labels:
- Events (15 messages)
- Personal (6 messages)
- Travel (3 messages)
```

Model is explicitly told:
- "PREFER reusing existing labels when they fit"
- "Only create new labels when existing ones don't match well"

**Result:** 50 emails → 4 labels (model consolidates aggressively!)

## Cost

### Haiku 4.5 (Default, Recommended)
- ~750 tokens per email
- ~$0.0006 per email
- ~$1.80/month for 100 emails/day
- **70,000 inbox emails = $42 one-time**

### Sonnet 4.5 (Higher Quality, 166x More Expensive)
- ~750 tokens per email
- ~$0.10 per email (actual production cost!)
- ~$300/month for 100 emails/day
- **70,000 inbox emails = $7,000 one-time** 😱

**Recommendation:** 
- Use **Haiku** for bulk processing (default)
- Use **Sonnet** only for testing or when you need highest quality
- Start with inbox, process in batches with `--last 1000` or use `--last 0` for everything

## Bulk Processing (70k+ Emails)

Want to process your entire inbox history? Here's how:

### Option 1: Process Everything at Once

```bash
# Process ALL unprocessed emails (auto-pagination)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute
```

This will:
- Automatically paginate through ALL unprocessed emails
- Fetch 500 emails per page (Gmail API limit)
- Show progress as it goes
- Cost: ~$0.0006/email with Haiku

### Option 2: Process in Batches

```bash
# Process 1000 emails at a time (recommended for safety)
bin/schemail process --last 1000 --classifier experiment-3 --model haiku-4-5 --execute

# Run again for next 1000 (automatically skips processed)
bin/schemail process --last 1000 --classifier experiment-3 --model haiku-4-5 --execute
```

### Option 3: Process by Time Period

```bash
# Process last week
bin/schemail process --last-days 7 --classifier experiment-3 --model haiku-4-5 --execute

# Process today only
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute

# Process specific date range
bin/schemail process --since "2026-01-01" --classifier experiment-3 --model haiku-4-5 --execute
```

### Option 4: Daemon Mode (Automatic)

```bash
# Run continuously, process new emails every 5 minutes
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5
```

Press Ctrl+C to stop.

## Examples

### Example 1: Test on 10 Emails

```bash
$ bin/schemail process --last 10 --classifier experiment-3

Mode: DRY-RUN (will not modify emails)
Classifier: experiment-3

Fetching 10 emails (query: in:inbox -label:Schemail)...
Found 10 message(s)

━━━ MESSAGE 1/10 ━━━
From: Alice Example <alice@example.com>
Subject: Meeting agenda for next month

Label: Travel
Archive: false
Rationale: Defer - requires review of agenda and decision on dates

━━━ MESSAGE 2/10 ━━━
From: LinkedIn <messages-noreply@linkedin.com>
Subject: People are viewing your LinkedIn profile

Label: Newsletter
Archive: true
Rationale: Automated notification - no action needed
```

### Example 2: Process 50 Emails Live

```bash
$ bin/schemail process --last 50 --classifier experiment-3 --execute

Mode: LIVE (will modify emails)
Classifier: experiment-3

[... processes 50 emails ...]

✓ Done processing all messages!

=== Applying 'rainbow' color scheme ===
Found 4 user label(s), 4 with messages (0 empty, skipped)

  [1/4] Travel (6 msgs) → bg:#285bac text:#ffffff
  [2/4] Events (31 msgs) → bg:#44b984 text:#000000
  [3/4] Personal (8 msgs) → bg:#fad165 text:#000000
  [4/4] Jobs (5 msgs) → bg:#cc3a21 text:#ffffff

✓ Applied colors to 4 label(s)!
```

### Example 3: Clean Up and Reprocess

```bash
# Remove all labels to start fresh
$ bin/schemail labels cleanup
# Type "yes" to confirm

# Reprocess
$ bin/schemail process --last 50 --classifier experiment-3 --execute
```

## Troubleshooting

### OAuth Issues

**Problem:** Token expired or corrupted

**Solution:**
```bash
# Remove corrupted token
rm ~/.oauth2.rkt/tokens

# Re-run (will trigger OAuth flow)
bin/schemail process --last 1 --classifier experiment-3
```

### Labels Not Applying

**Problem:** Dry-run mode active (forgot `--execute`)

**Solution:** Add `--execute` flag:
```bash
bin/schemail process --last 10 --classifier experiment-3 --execute
```

### Too Many Labels Created

**Problem:** Model creating too many specific labels

**Solutions:**
1. Run on more emails (consolidation improves with scale)
2. Use Experiment 3 (most aggressive consolidation)
3. Clean up and reprocess (labels hash will help)

### API Rate Limits

**Problem:** Processing too many emails too fast

**Solution:**
- Process in smaller batches (50-100 at a time)
- Add delays between batches
- Claude API is quite generous (shouldn't hit limits normally)

## Next Steps

### After Initial Processing

1. **Review labels in Gmail** - Check if categories make sense
2. **Manually adjust if needed** - Rename labels, merge similar ones
3. **Reprocess to consolidate** - Run again, model will reuse your labels
4. **Set up regular processing** - Process new emails daily/weekly

### Advanced Usage

**Process specific labels:**
```bash
bin/schemail process --query "label:Newsletters" --classifier experiment-3 --execute
```

**Reprocess everything:**
```bash
bin/schemail process --query "-label:Schemail" --last 1000 --classifier experiment-3 --execute
```

**Process archives:**
```bash
bin/schemail process --query "in:all -label:Schemail" --last 500 --classifier experiment-3 --execute
```

## Documentation

- **[README.md](README.md)** - Full project overview
- **[docs/daemon-mode.md](docs/daemon-mode.md)** - Complete daemon mode guide
- **[TODO.md](TODO.md)** - Development roadmap
- **[notes/classifier-experiments.md](notes/classifier-experiments.md)** - Detailed test results
- **[notes/flat-label-experiment-results.md](notes/flat-label-experiment-results.md)** - Flat vs nested comparison

## Philosophy

**Inbox Zero principles:**
- Inbox = Todo list (not archive)
- Process emails quickly
- Archive after action
- Labels for context, not storage

**Flat labels:**
- Simple beats complex at small scale
- No wasted empty parents
- Model chooses semantically meaningful categories
- Room to grow as needed

**AI-first:**
- High-level instructions, not specific rules
- Model learns from existing labels
- Handles edge cases gracefully
- Adapts to your email patterns

---

**Ready to get started? Run your first 10 emails!**

```bash
bin/schemail process --last 10 --classifier experiment-3
```
