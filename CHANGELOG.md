# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Polling daemon for automatic email processing
- Web UI for monitoring and stats
- Caching layer for LLM responses
- Rate limiting and retry logic

## [0.2.0] - 2026-02-14 🚀

### Added - LLM Integration (Agentic Approach)

**Core Features:**
- Claude Sonnet 4.5 integration with tool calling (`src/llm.rkt`)
- 5 tools for Claude: apply_label, archive_email, star_email, mark_as_read, do_nothing
- High-level email classification prompt (`config/preferences.rkt`)
- Comprehensive test suite (`src/test-llm.rkt`) with 4 test modes
- Dry-run mode for safe testing
- Token usage tracking and cost monitoring
- Error handling and API response parsing

**Filter DSL Enhancements:**
- `(llm-agent preferences)` action for agentic processing
- `(always)` condition for fallback filters
- `(subject-contains pattern)` condition
- Dry-run support throughout filter execution
- Pass full message objects to actions (not just IDs)

**Configuration:**
- `config/preferences.rkt` - High-level email handling instructions
- `config/filters.rkt` - Three filter strategies (pure LLM, hybrid, selective)

**Documentation:**
- `notes/agentic.md` - Complete implementation guide
- `QUICKSTART.md` - Quick start guide
- `CHANGELOG.md` - This file
- Updated `TODO.md` with Phase 2 completion status
- Updated `README.md` with status banner

### Test Results

**First Production Test - 5 emails:**
- Accuracy: 5/5 (100%)
- Average tokens per email: 1,456 input, 159 output
- Cost per email: ~$0.007
- All automated notifications correctly classified

Tested emails:
- Amazon shipping notification ✅
- Anthropic receipts (3x) ✅
- GoDaddy order confirmation ✅

### Technical Details

**Model:** claude-sonnet-4-20250514 (Claude Sonnet 4.5)
**API:** Anthropic Messages API with tool calling
**Cost:** ~$0.007 per email (~$20/month for 100 emails/day)
**Alternative:** claude-haiku-4-5 available (~$0.002 per email)

**Dependencies Added:**
- `http-easy` (Racket package for HTTP requests)
- `actor-lib`, `resource-pool-lib` (transitive dependencies)

### Architecture

**Approach:** Tool Calling (Approach 2 from NOTES.md)
- LLM receives email + tools + high-level instructions
- LLM decides which tools to call and with what parameters
- System executes tool calls via Gmail API
- Fully autonomous decision-making

**Files Added:**
- `src/llm.rkt` (298 lines) - Core LLM integration
- `config/preferences.rkt` (31 lines) - Email assistant prompt
- `src/test-llm.rkt` (179 lines) - Test suite
- `config/filters.rkt` (79 lines) - Filter strategies
- `notes/agentic.md` (852 lines) - Implementation docs
- `QUICKSTART.md` - User guide
- `CHANGELOG.md` - This file

**Files Modified:**
- `src/filters.rkt` - Added llm-agent action, dry-run support
- `TODO.md` - Updated Phase 2 & 3 status
- `README.md` - Added status banner
- `NOTES.md` - (previously created) LLM approaches

### Breaking Changes

None. All existing filter DSL functionality preserved.

### Lessons Learned

1. **Tool calling works brilliantly** - Claude makes smart decisions with minimal guidance
2. **High-level prompts are sufficient** - No need for examples or fine-tuning
3. **Dry-run mode is essential** - Made testing safe and confidence-building
4. **Cost is acceptable** - ~$20/month for personal use is reasonable
5. **Racket is perfect for this** - S-expressions make config elegant

### Known Issues

- None currently. System working as designed.

### Next Steps

**Phase 4: Polling Daemon**
- Fetch new emails periodically (every 1-5 minutes)
- Process with filter pipeline
- Graceful shutdown and error handling
- Systemd service for background running

## [0.1.0] - 2026-02-12

### Added - Foundation

**Gmail OAuth Flow:**
- Custom OAuth URL builder for refresh tokens
- Token persistence to `~/.oauth2.rkt/tokens`
- Automatic token refresh
- Integration with `simple-oauth2` package

**Gmail API Wrapper (`src/gmail.rkt`):**
- `gmail-list-messages` - Fetch messages with query support
- `gmail-get-message` - Get full message details
- `gmail-modify-message` - Modify labels
- `gmail-batch-modify` - Batch operations
- `gmail-list-labels`, `gmail-get-label`, `gmail-create-label`
- `gmail-find-label-by-name` - Helper for label lookup
- Helper functions: message-subject, message-from, message-date, etc.

**Filter DSL (`src/filters.rkt`):**
- S-expression syntax for filters
- Conditions: from, to, subject, body, has-label, and, or, not
- Actions: label, archive, star, mark-read, skip
- Automatic label creation
- Filter evaluation engine
- Action composition

**Test Scripts:**
- `src/test-oauth.rkt` - OAuth flow testing
- `src/test-gmail.rkt` - Gmail API testing
- `src/test-filters.rkt` - Filter DSL testing

**Configuration:**
- `config/credentials.json` - OAuth credentials
- `config/filters.example.rkt` - Example filters
- `.gitignore` - Protects credentials

**Documentation:**
- `README.md` - System design and rationale
- `TODO.md` - Development roadmap

### Test Results

All integration tests passing:
- OAuth flow ✅
- Gmail API CRUD operations ✅
- Filter DSL evaluation ✅
- Label auto-creation ✅

Tested on real emails (Anthropic receipts).

---

## Format

This changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.

Versions use [Semantic Versioning](https://semver.org/):
- MAJOR version for incompatible API changes
- MINOR version for new functionality (backwards compatible)
- PATCH version for backwards compatible bug fixes
