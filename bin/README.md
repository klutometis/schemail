# schemail CLI

The `schemail` command-line tool for intelligent email filtering.

## Installation

Add to your PATH:
```bash
ln -s /home/danenberg/prg/email/bin/schemail ~/bin/schemail
```

Or use directly:
```bash
./bin/schemail help
```

## Usage



╔════════════════════════════════════════════════════════════╗
║                                                            ║
║  schemail - Intelligent Email Filtering                   ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

USAGE:
  schemail process [OPTIONS]     Process emails through filters
  schemail daemon [OPTIONS]      Run as daemon (polls for new emails)
  schemail test                  Run test suite
  schemail help                  Show this help

PROCESS OPTIONS:
  --last N                  Process last N emails (default: 10)
  --unread                  Process only unread emails
  --since DATE              Process emails since date (YYYY-MM-DD)
  --until DATE              Process emails until date (YYYY-MM-DD)
  --query "QUERY"           Custom Gmail query
  
  --filter STRATEGY         Filter strategy to use (default: hybrid)
                            Options: hybrid, pure-llm, selective-llm
  
  --execute                 Actually execute actions (default: dry-run)
  --dry-run                 Only show what would happen (default)
  
  --interactive             Interactively review each email
  --verbose                 Show detailed output

DAEMON OPTIONS:
  --interval N              Poll interval in minutes (default: 5)
  --query "QUERY"           Gmail query for emails to process

EXAMPLES:
  # Dry-run on last 10 emails (safe)
  schemail process --last 10
  
  # Actually process last 50 emails with hybrid strategy
  schemail process --last 50 --filter hybrid --execute
  
  # Process unread emails only
  schemail process --unread --execute
  
  # Process emails from last week
  schemail process --since "2026-02-07" --execute
  
  # Interactive mode (review each email)
  schemail process --last 20 --interactive
  
  # Run as daemon (checks every 5 minutes)
  schemail daemon --interval 5

FILTER STRATEGIES:
  hybrid       - Fast pattern matching + LLM fallback (recommended)
  pure-llm     - LLM processes every email (slow, expensive)
  selective-llm - Pattern matching first, LLM only for ambiguous cases

NOTES:
  - Default mode is DRY-RUN for safety
  - Use --execute to actually modify emails
  - First run will trigger OAuth flow
  - Costs ~$0.007 per email with LLM (~$20/month for 100/day)

