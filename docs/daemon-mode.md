# Daemon Mode

## Overview

Daemon mode runs continuously and automatically processes new emails as they arrive by polling Gmail at regular intervals.

## How It Works

### Timestamp Granularity Problem

Gmail search API only supports **DATE-level granularity**, not timestamps:
- `after:2026-02-16` - Matches all emails from that date
- `newer_than:1d` - Matches emails from last 24 hours
- **No support for**: `after:2026-02-16T14:30:00` ❌

But daemon polls every N minutes (e.g., every 5 minutes), so we need **minute-level granularity** to avoid reprocessing the same emails.

### Solution: Label-Based Tracking

Instead of timestamps, we use the `Schemail` label as a **processed marker**:

1. Daemon queries: `in:inbox -label:Schemail`
2. Finds all emails WITHOUT the `Schemail` label
3. Processes each email (classify, archive, etc.)
4. Applies `Schemail` label to mark as processed
5. Next poll won't see those emails (they have the label now)

This provides **minute-level granularity** without needing timestamp support.

## Modes

### Default Mode: Process All Unprocessed

```bash
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5
```

**Query:** `in:inbox -label:Schemail`

**Behavior:**
- Processes up to 50 emails per poll
- Includes ALL unprocessed emails (new and old backlog)
- If you have 5,000 old unprocessed emails, will churn through them 50 at a time
- Takes 100 polls (8+ hours at 5-min intervals) to clear 5,000 email backlog

**Good for:**
- Fresh inbox with no backlog
- You want daemon to slowly catch up on backlog while handling new emails

### Recent-Only Mode: Ignore Backlog

```bash
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

**Query:** `in:inbox -label:Schemail newer_than:1d`

**Behavior:**
- Only processes emails from last 24 hours
- Completely ignores old backlog
- Focuses on NEW incoming emails only

**Good for:**
- You have large backlog but want daemon to handle only NEW emails
- After clearing backlog, keep monitoring ongoing

## Recommended Workflow

### Option 1: Clear Backlog First (Recommended)

```bash
# Step 1: Clear backlog in one shot (might take hours for 70k emails)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Step 2: Start daemon in recent-only mode
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

**Cost for 70k backlog:** ~$42 with Haiku

### Option 2: Let Daemon Catch Up Slowly

```bash
# Start daemon without --recent-only
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5
```

**Behavior:**
- Processes 50 emails every 5 minutes
- Takes ~1 hour per 600 emails
- 5,000 emails = ~8 hours
- 70,000 emails = ~117 hours (5 days)

**Good for:** Low urgency, want to spread cost over time

### Option 3: Hybrid Approach

```bash
# Process last week's backlog
bin/schemail process --last-days 7 --classifier experiment-3 --model haiku-4-5 --execute

# Start daemon for very recent emails only
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

## Command Reference

### Basic Usage

```bash
# Run with Haiku (cheap), poll every 5 minutes
bin/schemail daemon --classifier experiment-3 --model haiku-4-5 --interval 5

# Run with Sonnet (expensive), poll every 10 minutes
bin/schemail daemon --classifier experiment-3 --model sonnet-4-5 --interval 10

# Recent-only mode (ignore backlog)
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

### Custom Query

You can override the default query:

```bash
# Only process unread emails
bin/schemail daemon --query "is:unread -label:Schemail" --interval 5

# Only process from specific sender
bin/schemail daemon --query "from:important@company.com -label:Schemail" --interval 5

# Combine with recent-only manually
bin/schemail daemon --query "in:inbox -label:Schemail newer_than:1d" --interval 5
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--interval N` | Poll every N minutes | 5 |
| `--recent-only` | Only process emails from last 24h | off |
| `--classifier EXPERIMENT` | Which classifier to use | none |
| `--model MODEL` | haiku-4-5 or sonnet-4-5 | haiku-4-5 |
| `--query "QUERY"` | Custom Gmail query | `in:inbox -label:Schemail` |

## What Daemon Does Each Poll

```
[2026-02-16 14:35:22] Checking for new emails...
  → Query: in:inbox -label:Schemail newer_than:1d
  → Found 3 new message(s), processing...
  
  MESSAGE 1/3: alice@example.com - "Quick question"
    Label: Personal
    Archive: false
  
  MESSAGE 2/3: receipts@uber.com - "Your trip receipt"
    Label: Receipts
    Archive: true
  
  MESSAGE 3/3: noreply@github.com - "You were mentioned in issue #123"
    Label: GitHub
    Archive: false
  
  ✓ Processed 3 message(s)
  ⏳ Sleeping for 5 minutes...
```

## Stopping the Daemon

Press **Ctrl+C** to stop gracefully.

The daemon will finish processing the current email before stopping.

## Error Handling

If an error occurs during processing, daemon logs the error and continues:

```
[2026-02-16 14:40:22] Checking for new emails...
⚠ Error: Gmail API rate limit exceeded
  Continuing...
  ⏳ Sleeping for 5 minutes...
```

The daemon will retry on the next poll.

## Running as a Service

### Using systemd (Linux)

Create `/etc/systemd/system/schemail.service`:

```ini
[Unit]
Description=Schemail Email Classifier Daemon
After=network.target

[Service]
Type=simple
User=yourusername
WorkingDirectory=/home/yourusername/prg/email
Environment="ANTHROPIC_API_KEY=your_api_key_here"
ExecStart=/home/yourusername/prg/email/bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable schemail
sudo systemctl start schemail
sudo systemctl status schemail
```

View logs:

```bash
sudo journalctl -u schemail -f
```

### Using tmux/screen (Simple)

```bash
# Start in tmux session
tmux new -s schemail
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5

# Detach: Ctrl+B, then D
# Reattach: tmux attach -t schemail
```

## Cost Analysis

### Haiku (Recommended)

**Scenario:** 100 new emails per day

- Cost per email: ~$0.0006
- Daily cost: $0.06
- Monthly cost: ~$1.80
- Yearly cost: ~$22

**Scenario:** 20 new emails per day

- Daily cost: $0.012
- Monthly cost: ~$0.36
- Yearly cost: ~$4.40

### Sonnet (Expensive)

**Scenario:** 100 new emails per day

- Cost per email: ~$0.10
- Daily cost: $10
- Monthly cost: ~$300
- Yearly cost: ~$3,650 😱

**Recommendation:** Use Haiku for daemon mode. Only use Sonnet for manual processing of important emails.

## Comparison with Gmail Push API (Pub/Sub)

| Feature | Daemon (Polling) | Push (Pub/Sub) |
|---------|-----------------|----------------|
| **Latency** | N minutes (configurable) | ~Instant (<1 min) |
| **Setup complexity** | None | High (Cloud setup required) |
| **Infrastructure** | Runs anywhere | Requires public endpoint |
| **Cost** | Free (just API calls) | ~$0.40/month (Cloud Run) |
| **Reliability** | Depends on uptime | Google handles it |
| **Localhost** | ✅ Works | ❌ Requires ngrok/tunnel |

**For most users:** Daemon mode (polling) is simpler and sufficient. 5-minute latency is fine for email processing.

**For power users:** See `todo/gmail-push-notifications.md` for Pub/Sub setup guide.

## Troubleshooting

### Daemon processes same emails repeatedly

**Problem:** Emails aren't getting the `Schemail` label

**Solution:** Check that you're NOT using `--dry-run`. Daemon always runs in live mode.

### Daemon is slow / churning through old emails

**Problem:** You have large backlog and daemon is processing 50 at a time

**Solutions:**
1. Stop daemon, run `bin/schemail process --last 0 --execute` to clear backlog
2. Use `--recent-only` flag to ignore backlog
3. Wait it out (daemon will eventually catch up)

### OAuth token expires

**Problem:** Daemon runs for >1 hour and token expires

**Solution:** The OAuth system should auto-refresh. If it fails:
```bash
# Remove token and re-authenticate
rm ~/.oauth2.rkt/tokens
# Restart daemon (will trigger OAuth flow)
```

### Gmail API rate limits

**Problem:** Processing too many emails too fast

**Solution:**
- Gmail API allows 250 quota units/user/second
- Each message fetch = 5 units
- Daemon should stay well under limits (max 50 emails per poll)
- If you hit limits, increase `--interval` value

## See Also

- [QUICKSTART.md](../QUICKSTART.md) - Basic usage
- [README.md](../README.md) - Full project overview
- [todo/gmail-push-notifications.md](../todo/gmail-push-notifications.md) - Real-time push setup
