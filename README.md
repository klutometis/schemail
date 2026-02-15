# Schemail - Intelligent Email Filtering with Claude AI

**Production-ready email classification system using Claude AI to automatically organize and filter Gmail.**

![Schemail Screenshot](assets/screenshot.png)

## What It Does

Schemail uses Claude Sonnet 4.5 to intelligently classify your emails into clean, flat labels and automatically archive non-actionable messages following Inbox Zero principles.

**Key Features:**
- 🤖 **AI-powered classification** - Claude decides labels and archive behavior
- 📊 **Flat label structure** - Simple, clean categories (no nested hierarchy)
- 🎨 **Automatic color coding** - Rainbow colors for visual organization
- ⚡ **Label reuse** - Model learns existing labels to prevent proliferation
- 🎯 **Inbox Zero friendly** - Only human-action emails stay in inbox
- 💰 **Cost-effective** - ~$0.003 per email (~$9/month for 100 emails/day)

**Tested Performance:**
- 50 emails → 4 labels (Events, Personal, Travel, Jobs)
- 62% automatically archived
- 38% kept in inbox for human action
- Zero empty parent labels

## Quick Start

### Prerequisites

- Racket 9.0+
- Gmail account with OAuth2 credentials
- Anthropic API key (Claude)

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
# Test on 10 emails (dry-run)
bin/classify

# Test on 50 emails (dry-run)
bin/classify 50

# Process 50 emails (live)
bin/classify 50 --live

# Process 200 emails (live, with auto-logging)
bin/classify 200 --live
```

**Manual way (full control):**

```bash
# Process last 10 emails (dry-run)
bin/schemail process --last 10 --classifier experiment-3

# Process last 50 emails (live)
bin/schemail process --last 50 --classifier experiment-3 --execute

# Process last 200 emails with logging
bin/schemail process --last 200 --classifier experiment-3 --execute 2>&1 | tee output.log

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
# Basic processing
bin/schemail process --last N --classifier experiment-3 --execute

# With custom query
bin/schemail process --query "label:INBOX -label:Schemail" --last 50 --classifier experiment-3 --execute

# Include already-processed emails
bin/schemail process --last 50 --classifier experiment-3 --include-processed --execute

# Process unread only
bin/schemail process --unread --classifier experiment-3 --execute

# Process by date range
bin/schemail process --since "2026-02-01" --until "2026-02-15" --classifier experiment-3 --execute
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
- **[TODO.md](TODO.md)** - Development roadmap
- **[notes/](notes/)** - Design decisions and experiments

### Key Documents

- `notes/classifier-experiments.md` - All experiment results and analysis
- `notes/flat-label-experiment-results.md` - Flat vs nested label comparison
- `notes/label-structure-evolution.md` - Label design evolution
- `notes/label-colors.md` - Color system design
- `notes/oauth-improvements.md` - OAuth token recovery

## Cost Analysis

**Per-email cost (Claude Sonnet 4.5):**
- Input: ~700 tokens × $3/M = $0.0021
- Output: ~50 tokens × $15/M = $0.00075
- **Total: ~$0.003 per email**

**Scaling scenarios:**
- 100 emails/day × 30 days = $9/month
- 72,762 inbox emails = $218 one-time (50-60 hours)
- 112,786 total emails = $338 one-time (78-94 hours)

## Roadmap

- [x] OAuth2 with automatic token refresh
- [x] Gmail API wrapper (full CRUD)
- [x] Structured classifier with Claude Sonnet 4.5
- [x] Three experiment prompts with testing
- [x] Flat label structure with color coding
- [x] Label reuse to prevent proliferation
- [ ] Daemon mode (polling for new emails)
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

Built with [Racket](https://racket-lang.org/) and [Claude](https://www.anthropic.com/claude) by [Peter Danenberg](https://github.com/klutometis).
