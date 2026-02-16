# Schemail Cheat Sheet

## Quick Commands

### Process Emails

```bash
# Test on 10 emails (dry-run, safe)
bin/schemail process --last 10 --classifier experiment-3 --model haiku-4-5

# Process today's emails (live)
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute

# Process last 2 days (live)
bin/schemail process --last-days 2 --classifier experiment-3 --model haiku-4-5 --execute

# Process ALL unprocessed (bulk, uses pagination)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Run daemon (poll every 5 minutes, ignore backlog)
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

### Label Management

```bash
# Apply rainbow colors
bin/schemail labels assign-colors --color-scheme rainbow

# Clean up all experiment labels
bin/schemail labels cleanup
```

## Flags

### Time-Based

| Flag | Description | Example |
|------|-------------|---------|
| `--last N` | Process last N emails | `--last 100` |
| `--last 0` | Process ALL matching (pagination) | `--last 0` |
| `--today` | Last 24 hours (no count limit) | `--today` |
| `--last-days N` | Last N days (no count limit) | `--last-days 7` |
| `--since DATE` | From specific date | `--since "2026-02-01"` |

### Models

| Flag | Cost/email | Use Case |
|------|-----------|----------|
| `--model haiku-4-5` | $0.0006 | Default, bulk processing |
| `--model sonnet-4-5` | $0.10 | Important emails, testing |

### Classifiers

| Flag | Description |
|------|-------------|
| `--classifier experiment-3` | Recommended (Inbox Zero) |
| `--classifier experiment-2` | High-level principles |
| `--classifier experiment-1` | Blank slate |

### Execution

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would happen (default) |
| `--execute` | Actually apply changes (live) |

### Daemon

| Flag | Description |
|------|-------------|
| `--interval N` | Poll every N minutes (default: 5) |
| `--recent-only` | Only process last 24h (ignore backlog) |

## Workflows

### First-Time Setup

```bash
# 1. Install dependencies
raco pkg install simple-oauth2 http-easy

# 2. Setup OAuth credentials (config/credentials.json)
# 3. Set Anthropic API key
export ANTHROPIC_API_KEY=your_key_here

# 4. Test on 10 emails
bin/schemail process --last 10 --classifier experiment-3 --model haiku-4-5
```

### Clear Backlog + Start Daemon

```bash
# Step 1: Clear all backlog (one-time)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Step 2: Start daemon for new emails
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

### Daily Processing

```bash
# Process today's emails
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute
```

### Weekly Catchup

```bash
# Process last week
bin/schemail process --last-days 7 --classifier experiment-3 --model haiku-4-5 --execute
```

## Cost Estimates

### Haiku (Recommended)

| Scenario | Cost |
|----------|------|
| 10 emails | $0.006 |
| 100 emails | $0.06 |
| 1,000 emails | $0.60 |
| 10,000 emails | $6 |
| 70,000 emails | $42 |
| 100 emails/day × 30 days | $1.80/month |

### Sonnet (Expensive)

| Scenario | Cost |
|----------|------|
| 10 emails | $1 |
| 100 emails | $10 |
| 1,000 emails | $100 |
| 70,000 emails | $7,000 😱 |
| 100 emails/day × 30 days | $300/month |

## Troubleshooting

### Problem: Token expired

```bash
rm ~/.oauth2.rkt/tokens
bin/schemail process --last 1 --classifier experiment-3 --model haiku-4-5
```

### Problem: Too many labels created

```bash
# Clean up and reprocess
bin/schemail labels cleanup
bin/schemail process --last 50 --classifier experiment-3 --model haiku-4-5 --execute
```

### Problem: Daemon processing old emails

```bash
# Use --recent-only flag
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

## Query Examples

```bash
# Only unread
--query "is:unread -label:Schemail"

# From specific sender
--query "from:boss@company.com -label:Schemail"

# Specific label
--query "label:Newsletters -label:Schemail"

# Date range
--since "2026-02-01" --until "2026-02-15"
```

## Files

| File | Description |
|------|-------------|
| `config/schemail.rkt` | User config (color scheme, etc.) |
| `config/credentials.json` | OAuth credentials (from Google Cloud) |
| `~/.oauth2.rkt/tokens` | OAuth token cache |
| `/tmp/schemail-classify-*.log` | Auto-generated logs |

## Help

```bash
bin/schemail help
```

## Full Documentation

- [README.md](../README.md) - Project overview
- [QUICKSTART.md](../QUICKSTART.md) - Detailed setup
- [docs/daemon-mode.md](daemon-mode.md) - Daemon deep dive
- [docs/README.md](README.md) - Full doc index
