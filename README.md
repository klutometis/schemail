# Schemail - Intelligent Email Filtering

**Production-ready email classification system using AI to automatically organize and filter Gmail.**

![Schemail Screenshot](assets/screenshot.png)

## What It Does

Schemail uses large language models to intelligently classify your emails into clean, flat labels and automatically archive non-actionable messages following Inbox Zero principles.

**Key Features:**
- 🤖 **AI-powered classification** - LLM decides labels and archive behavior
- 📊 **Flat label structure** - Simple, clean categories (no nested hierarchy)
- 🎨 **Automatic color coding** - Rainbow colors for visual organization
- ⚡ **Label reuse** - Model learns existing labels to prevent proliferation
- 🎯 **Inbox Zero friendly** - Only human-action emails stay in inbox
- 💰 **Cost-effective** - Haiku: ~$0.0006/email (~$0.18/month), Sonnet: ~$0.10/email (~$300/month)
- 🔄 **Daemon mode** - Automatic processing of new emails every N minutes
- ⚡ **Bulk processing** - Pagination support for processing 70k+ emails

**Tested Performance:**
- 50 emails → 4 labels (Events, Personal, Travel, Jobs)
- 62% automatically archived
- 38% kept in inbox for human action
- Zero empty parent labels

## Quick Start

### Prerequisites

- Racket 9.0+
- Gmail account with OAuth2 credentials
- Anthropic API key

### Installation

```bash
# Clone the repo
git clone https://github.com/klutometis/schemail.git
cd schemail

# Install Racket dependencies
raco pkg install simple-oauth2 http-easy

# Set up OAuth and API keys
# Follow QUICKSTART.md for detailed setup
```

### Basic Usage

**Easy way (using wrapper script):**

```bash
# Test on 10 emails with Haiku (dry-run)
bin/classify

# Process 50 emails with Haiku (live, cheap)
bin/classify 50 --live

# Process 200 emails with Haiku (live, with auto-logging)
bin/classify 200 --live
```

**Manual way (full control):**

```bash
# Process last 10 emails with Haiku (dry-run, cheap)
bin/schemail process --last 10 --classifier experiment-3 --model haiku-4-5

# Process today's emails with Haiku (all from last 24 hours)
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute

# Process last 2 days with Haiku (no limit on count)
bin/schemail process --last-days 2 --classifier experiment-3 --model haiku-4-5 --execute

# Process ALL unprocessed emails with Haiku (uses pagination)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Run as daemon (polls every 5 minutes, automatic processing)
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5

# Use expensive Sonnet for important emails
bin/schemail process --last 50 --classifier experiment-3 --model sonnet-4-5 --execute

# Apply colors to existing labels
bin/schemail labels assign-colors --color-scheme rainbow

# Clean up all experiment labels
bin/schemail labels cleanup
```

### Configuration

Edit `config/schemail.rkt`:

```racket
;; Color scheme: rainbow (unlimited colors)
(define color-scheme 'rainbow)

;; Labels to exclude from coloring
(define exclude-from-coloring '("Groups" "Saved"))
```

## How It Works

### Classifier Experiments

Schemail includes three experimental prompts tested at scale:

1. **Experiment 1** - Blank slate with minimal guidance
2. **Experiment 2** - High-level Inbox Zero principles
3. **Experiment 3** - Explicit Inbox Zero framework ⭐ **Recommended**

**Experiment 3 (default)** uses explicit Delete/Delegate/Respond/Defer/Do principles:
- Automated emails (receipts, notifications) → Archive immediately
- Personal emails (real people) → Keep in inbox for response
- Results: 50 emails → 4 flat labels, excellent discrimination

### Label Structure

**Flat labels (no hierarchy):**
- Simple, single-word or short-phrase labels
- Model chooses spontaneously: `Events`, `Personal`, `Travel`, `Jobs`
- No empty parent labels wasting space
- All labels get colors

**Why flat?**
- At small scale (4-10 labels), nesting adds no value
- Simpler UI, easier to understand
- Zero wasted empty parents
- Room to grow as needed

### Performance

**Scaling characteristics:**
- 10 emails → 4 labels (40% ratio)
- 50 emails → 4 labels (8% ratio) ⭐ Better consolidation at scale!
- Label reuse increases with volume
- Model recognizes patterns (e.g., all Anthropic receipts → Receipt)

**Cost estimation:**
- Per email: ~750 tokens (~$0.003)
- 100 emails/day: ~$9/month
- 72,762 inbox emails: ~$218 total (~50-60 hours)

## Label System

### Flat Label Examples

Model spontaneously creates semantic categories:
- **Events** - Invitations, meetings, RSVPs
- **Personal** - Human conversations, discussions
- **Travel** - Airlines, hotels, loyalty programs
- **Jobs** - Recruiting, opportunities
- **Receipt** - Transactions, confirmations
- **Newsletter** - Marketing, updates

### Archive Behavior

**Kept in inbox (38%):**
- Real event invitations requiring RSVP
- Personal messages from humans
- Job opportunities requiring decision
- Anything needing human action

**Automatically archived (62%):**
- Luma event notifications
- Transactional receipts
- Welcome emails
- One-time passcodes
- Marketing newsletters

## Architecture

### Components

- **`src/llm-classifier.rkt`** - Structured classifier using Claude API
- **`src/label-utils.rkt`** - Label creation, normalization, application
- **`src/colors.rkt`** - 15 color schemes (ColorBrewer + Paul Tol + rainbow)
- **`src/label-colors.rkt`** - Gmail color palette mapping
- **`src/gmail.rkt`** - Gmail API wrapper
- **`src/oauth.rkt`** - OAuth2 with automatic token refresh
- **`config/classifier-prompts.rkt`** - Three experiment prompts
- **`config/schemail.rkt`** - User configuration
- **`bin/schemail`** - CLI interface

### Data Flow

```
Gmail API
  ↓ (fetch unprocessed emails)
Fetch labels once (hash table)
  ↓ (pass through pipeline)
For each email:
  ↓ (provide existing labels to model)
Claude Classifier
  ↓ (returns: label, should_archive, rationale)
Label Utilities
  ↓ (normalize, create if needed, apply)
Update labels hash
  ↓ (reuse for next email)
Gmail API (apply labels + archive)
  ↓ (at end of batch)
Color Assignment (rainbow scheme)
```

**Key optimization:** Labels fetched once, passed through pipeline, prevents O(n²) API calls.

## Commands

### Process Emails

```bash
# Basic processing with Haiku (cheap)
bin/schemail process --last N --classifier experiment-3 --model haiku-4-5 --execute

# Process today's emails (last 24 hours, no count limit)
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute

# Process last N days (no count limit, auto-pagination)
bin/schemail process --last-days 7 --classifier experiment-3 --model haiku-4-5 --execute

# Process ALL unprocessed emails (pagination for 70k+ emails)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Run as daemon (polls every 5 minutes)
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5

# With custom query
bin/schemail process --query "label:INBOX -label:Schemail" --last 50 --classifier experiment-3 --model haiku-4-5 --execute

# Include already-processed emails
bin/schemail process --last 50 --classifier experiment-3 --model haiku-4-5 --include-processed --execute

# Process unread only
bin/schemail process --unread --classifier experiment-3 --model haiku-4-5 --execute

# Process by date range
bin/schemail process --since "2026-02-01" --until "2026-02-15" --classifier experiment-3 --model haiku-4-5 --execute

# Use expensive Sonnet for better quality
bin/schemail process --last 50 --classifier experiment-3 --model sonnet-4-5 --execute
```

### Label Management

```bash
# Apply colors to all labels
bin/schemail labels assign-colors

# Apply specific color scheme
bin/schemail labels assign-colors --color-scheme rainbow

# Clean up experiment labels
bin/schemail labels cleanup
```

### Help

```bash
bin/schemail help
```

## Development

### Project Structure

```
schemail/
├── bin/
│   └── schemail              # CLI entry point
├── src/
│   ├── llm-classifier.rkt    # Claude API integration
│   ├── label-utils.rkt       # Label operations
│   ├── gmail.rkt             # Gmail API wrapper
│   ├── oauth.rkt             # OAuth2 flow
│   ├── colors.rkt            # Color schemes
│   └── label-colors.rkt      # Gmail color mapping
├── config/
│   ├── schemail.rkt          # User config
│   ├── classifier-prompts.rkt # Experiment prompts
│   └── filters.rkt           # Legacy filter DSL
├── notes/                    # Design documents
│   ├── classifier-experiments.md
│   ├── flat-label-experiment-results.md
│   ├── label-structure-evolution.md
│   └── ...
├── assets/
│   └── screenshot.png
├── README.md
├── QUICKSTART.md
└── TODO.md
```

### Testing

```bash
# Test on 10 emails (dry-run)
bin/schemail process --last 10 --classifier experiment-3

# Test OAuth refresh
racket src/test-refresh.rkt
```

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Detailed setup guide
- **[docs/cheatsheet.md](docs/cheatsheet.md)** - Quick reference card
- **[docs/daemon-mode.md](docs/daemon-mode.md)** - How daemon mode works (timestamp granularity, polling, etc.)
- **[docs/README.md](docs/README.md)** - Full documentation index
- **[TODO.md](TODO.md)** - Development roadmap
- **[notes/](notes/)** - Design decisions and experiments

### Key Documents

- `docs/daemon-mode.md` - Complete daemon mode guide (polling, timestamps, systemd)
- `notes/classifier-experiments.md` - All experiment results and analysis
- `notes/flat-label-experiment-results.md` - Flat vs nested label comparison
- `notes/label-structure-evolution.md` - Label design evolution
- `notes/label-colors.md` - Color system design
- `notes/oauth-improvements.md` - OAuth token recovery
- `todo/gmail-push-notifications.md` - Real-time push setup (alternative to polling)

## Cost Analysis

### Model Comparison

**Haiku 4.5 (Recommended, default):**
- Input: ~700 tokens × $1/M = $0.0007
- Output: ~50 tokens × $5/M = $0.00025
- **Total: ~$0.0006 per email**
- 100 emails/day × 30 days = **$1.80/month**
- 70,000 inbox emails = **$42 one-time**

**Sonnet 4.5 (Higher quality, 166x more expensive):**
- Input: ~700 tokens × $3/M = $0.0021
- Output: ~50 tokens × $15/M = $0.00075
- **Total: ~$0.10 per email** (actual production cost, not $0.003!)
- 100 emails/day × 30 days = **$300/month**
- 70,000 inbox emails = **$7,000 one-time**

**Recommendation:** Use Haiku for bulk processing, Sonnet only for important emails or quality testing.

## Roadmap

- [x] OAuth2 with automatic token refresh
- [x] Gmail API wrapper (full CRUD)
- [x] Structured classifier with Claude Haiku 4.5 and Sonnet 4.5
- [x] Three experiment prompts with testing
- [x] Flat label structure with color coding
- [x] Label reuse to prevent proliferation
- [x] Daemon mode (polling for new emails)
- [x] Pagination for bulk processing (70k+ emails)
- [x] Time-based filtering (--today, --last-days)
- [ ] Calendar integration (action-based event extraction)
- [ ] Gmail Push API (Pub/Sub for real-time)
- [ ] Web UI for viewing stats

## Contributing

This is a personal project, but suggestions and discussions welcome! Open an issue or PR.

## License

MIT License - See LICENSE file for details

## Related Projects

- [Inbox Zero](https://www.getinboxzero.com/) - Inspiration for label structure
- [simple-oauth2](https://github.com/johnstonskj/simple-oauth2) - Racket OAuth library
- [http-easy](https://github.com/Bogdanp/http-easy) - Racket HTTP client

## Credits

Built with [Racket](https://racket-lang.org/) by [Peter Danenberg](https://github.com/klutometis).
