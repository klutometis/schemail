# Schemail Documentation

## Getting Started

- **[QUICKSTART.md](../QUICKSTART.md)** - Setup and first steps
- **[README.md](../README.md)** - Project overview and features

## Guides

- **[daemon-mode.md](daemon-mode.md)** - Running schemail as a daemon
  - Timestamp granularity and how polling works
  - Default vs recent-only modes
  - Running as systemd service
  - Cost analysis and troubleshooting

## Reference

### Configuration
- `config/schemail.rkt` - User configuration (color scheme, excluded labels)
- `config/classifier-prompts.rkt` - Three experiment prompts
- `config/filters.rkt` - Legacy filter DSL (deprecated)

### Design Documents (`notes/`)

**Classifier:**
- `classifier-experiments.md` - All three experiments tested at scale
- `structured-classifier.md` - How the classifier system works

**Labels:**
- `flat-label-experiment-results.md` - Flat vs nested comparison (flat won)
- `label-structure-evolution.md` - Journey from nested to flat
- `label-structure.md` - Early label design thoughts
- `label-reuse-strategies.md` - Three approaches to label reuse
- `label-colors.md` - Color system design
- `migration-to-flat-labels.md` - Migration notes

**Infrastructure:**
- `oauth-improvements.md` - OAuth token refresh and recovery
- `mobile-label-visibility-issue.md` - Schemail label visible on mobile
- `color-schemes-survey.md` - Analysis of 15 color schemes

**Future:**
- `agentic.md` - Ideas for agentic email processing

### TODO Documents (`todo/`)

- `gmail-push-notifications.md` - Complete guide for real-time push (Pub/Sub)
- `label-consolidation.md` - Ideas for merging similar labels

## Command Reference

### Process Emails

```bash
# Basic processing
bin/schemail process --last N --classifier experiment-3 --model haiku-4-5 --execute

# Time-based
bin/schemail process --today --classifier experiment-3 --model haiku-4-5 --execute
bin/schemail process --last-days 7 --classifier experiment-3 --model haiku-4-5 --execute

# Bulk processing (pagination)
bin/schemail process --last 0 --classifier experiment-3 --model haiku-4-5 --execute

# Daemon mode
bin/schemail daemon --recent-only --classifier experiment-3 --model haiku-4-5 --interval 5
```

### Label Management

```bash
# Apply colors
bin/schemail labels assign-colors --color-scheme rainbow

# Hide labels
bin/schemail labels hide-except Schemail

# Clean up
bin/schemail labels cleanup
```

### Help

```bash
bin/schemail help
```

## Models

| Model | Cost/email | Speed | Quality | Use Case |
|-------|-----------|-------|---------|----------|
| **haiku-4-5** | $0.0006 | Fast | Good | Default, bulk processing |
| **sonnet-4-5** | $0.10 | Medium | Excellent | Important emails only |

## Architecture

```
bin/schemail (CLI)
  ↓
src/
  ├── llm-classifier.rkt    # Claude API integration
  ├── label-utils.rkt       # Label operations
  ├── gmail.rkt             # Gmail API wrapper
  ├── oauth.rkt             # OAuth2 flow
  ├── colors.rkt            # 15 color schemes
  └── label-colors.rkt      # Gmail color mapping
  ↓
config/
  ├── schemail.rkt          # User config
  └── classifier-prompts.rkt # Experiment prompts
```

## Quick Links

- [GitHub](https://github.com/klutometis/schemail)
- [Anthropic Console](https://console.anthropic.com/) (API keys)
- [Google Cloud Console](https://console.cloud.google.com/) (OAuth credentials)
- [Gmail API Docs](https://developers.google.com/gmail/api)

## Philosophy

**Inbox Zero:**
- Inbox = Todo list (not archive)
- Process quickly, archive after action
- Labels for context, not storage

**Flat Labels:**
- Simple beats complex at small scale
- No wasted empty parents
- Model chooses semantic categories

**AI-First:**
- High-level instructions, not rules
- Model learns from existing labels
- Handles edge cases gracefully
