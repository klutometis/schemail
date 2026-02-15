# TODO

## Phase 1: Foundation

### Racket Setup
- [x] Install Racket (installed v9.0 to ~/racket)
- [x] Verify installation (`racket --version`, `raco --version`)
- [x] Set up project structure (src/, config/, etc.)
- [x] Create basic `#lang racket` hello world (src/hello.rkt works!)

### Gmail OAuth Flow
- [x] Register app in Google Cloud Console
- [x] Get OAuth2 credentials (client_id, client_secret)
- [x] Implement OAuth2 authorization URL generator (custom for access_type=offline)
- [x] Build callback web server (using simple-oauth2's redirect-server)
- [x] Exchange auth code for access token
- [x] Store/refresh tokens (encrypted in ~/.oauth2.rkt/tokens)
- [x] **Bonus:** Automatic token refresh when expired
- [x] **Bonus:** Persist tokens to disk (no re-auth on restart)

### Gmail API Wrapper
- [x] Implement basic HTTP client wrapper with bearer token auth
- [x] `gmail-list-messages` - GET /users/me/messages (with query support)
- [x] `gmail-get-message` - GET /users/me/messages/:id (with full content)
- [x] `gmail-modify-message` - POST /users/me/messages/:id/modify (for labels)
- [x] `gmail-batch-modify` - batch modify multiple messages
- [x] `gmail-list-labels` - GET /users/me/labels
- [x] `gmail-get-label` - GET /users/me/labels/:id
- [x] `gmail-create-label` - POST /users/me/labels
- [x] `gmail-find-label-by-name` - helper to find label ID by name
- [x] Helper functions: message-subject, message-from, message-date, message-snippet, etc.

## Phase 2: LLM Integration ✅ COMPLETE!

### LLM API Client
- [x] Decide on LLM provider (Anthropic Claude Sonnet 4.5)
- [x] Implement HTTP client for Claude API (using http-easy)
- [x] Tool calling integration (agentic approach - LLM decides actions)
- [x] Handle API errors and parse responses
- [x] Token usage tracking and cost monitoring

### Email Classification Logic
- [x] Extract relevant email fields (from, subject, body snippet, date)
- [x] Format prompt for LLM with high-level instructions
- [x] Parse tool call responses from Claude
- [x] Execute tools: apply_label, archive_email, star_email, mark_as_read, do_nothing
- [x] Dry-run mode for safe testing

### Implementation Details
- **Model:** claude-sonnet-4-20250514 (with haiku fallback option)
- **Cost:** ~$0.006 per email (~1450 input + 150 output tokens)
- **Approach:** Tool calling (Approach 2 from notes/agentic.md)
- **Files:** src/llm.rkt, config/preferences.rkt, src/test-llm.rkt
- **Test Results:** Successfully classified 5/5 emails correctly!

## Phase 3: Filter DSL ✅ COMPLETE!

### Filter Definition
- [x] Design S-expression syntax for filters
- [x] Implement filter evaluation engine
- [x] Support priority/ordering of filters (processes in order)
- [x] Support multiple actions per filter
- [x] **Implemented conditions:** from, to, subject, subject-contains, body, has-label, and, or, not, always
- [x] **Agentic filtering:** (llm-agent preferences) action for AI-powered processing
- [ ] **TODO:** llm-match condition (for binary yes/no LLM classification)

### Actions
- [x] `(label "Name")` - apply Gmail label (auto-creates if missing!)
- [x] `(archive)` - remove from inbox
- [x] `(star)` - star the message
- [x] `(mark-read)` - mark as read
- [x] `(skip)` - stop processing further filters
- [x] `(llm-agent preferences)` - use Claude to decide actions autonomously
- [x] Action composition (run multiple actions per filter)
- [x] Dry-run mode for all actions
- [ ] **TODO:** `(skip-inbox)` - bypass inbox on arrival (needs Gmail filters API)

### Config Loading
- [x] Created example filter config (config/filters.example.rkt)
- [x] Created working filter configs (config/filters.rkt with 3 strategies)
- [x] Created email preferences (config/preferences.rkt)
- [ ] Read filters from config file (integration with daemon)
- [ ] Hot-reload support (watch file for changes?)
- [ ] Validate filter definitions

## Phase 4: Core Loop

### Email Processing
- [ ] Fetch unread emails (or all, with pagination)
- [ ] For each email, run filters in priority order
- [ ] Stop on first match? Or run all matches?
- [ ] Execute actions for matched filters
- [ ] Log results (stdout, file, structured?)

### Batch Processing (Historical)
- [ ] Add flag/command for "process all inbox"
- [ ] Pagination for large inboxes
- [ ] Rate limiting (don't hammer Gmail/LLM APIs)
- [ ] Progress reporting

### Daemon Mode (Watch for New Email)
- [ ] **MVP: Simple polling** (every 1-5 minutes, good enough for personal use)
  - [ ] Basic loop: fetch unread, process, sleep, repeat
  - [ ] Configurable poll interval
  - [ ] Graceful shutdown (signal handling)
- [ ] **Upgrade: Gmail Push API (Pub/Sub)** - for the beauty of it
  - [ ] Create Google Cloud Pub/Sub topic + subscription
  - [ ] Call Gmail Watch API (`POST /users/me/watch`)
  - [ ] Set up webhook endpoint (or pull from Pub/Sub)
  - [ ] Renew watch every ~7 days (auto-renew logic)
  - [ ] Handle push notifications in real-time
  
  *Note: Start with polling (simple, works on laptop). Upgrade to Pub/Sub once*
  *working—not for necessity, but because personal projects should be beautiful.*
  *Show the world what real-time elegance looks like.*

## Phase 5: Polish

### Error Handling
- [ ] Graceful failures (network, API errors)
- [ ] Retry logic with backoff
- [ ] Don't lose emails if classification fails

### Logging
- [ ] Structured logging (which filter matched, actions taken)
- [ ] Debug mode (verbose output)
- [ ] Log file rotation?

### Testing
- [ ] Unit tests for filter matching
- [ ] Mock Gmail/LLM APIs for testing
- [ ] Integration test with real Gmail (test account)

### Distribution
- [ ] `raco exe` - compile to binary
- [ ] Document setup process
- [ ] Example config files
- [ ] Systemd service file (or equivalent for running as daemon)

## Phase 6: Nice-to-Have

### Calendar Integration (Separate Tool)
- [ ] **Action-based calendar classifier:** Similar to email classifier but for calendar actions
  - Extract event details from `Invitation` labeled emails
  - LLM decides: create_event, decline_event, request_more_info, do_nothing
  - Parse: date, time, location, attendees from email body
  - Create Google Calendar events with email reference
- [ ] **Implementation options:**
  - Separate tool (`schemcal`) that reads labeled emails
  - CLI: `schemail calendar sync --label "Invitation"`
  - OAuth for Google Calendar API
  - Duplicate detection (don't create event if already exists)
- [ ] **Integration points:**
  - Reads emails with `Invitation` or `Meeting` labels
  - Optional: Update events on RSVP changes
  - Optional: Extract meeting times from `Planning` emails
- **Status:** TODO for Phase 5+, document action-based approach

### Label Structure Evolution
- [ ] **Test flat labels at scale (200 emails):**
  - Current: 6 nested labels (Event/Invitation, Action Required/Response, Meeting/Planning)
  - Proposal: 6 flat labels (Receipt, Newsletter, Notification, Invitation, Response, Planning)
  - Question: Do nested labels add value at small scale (6 labels)?
  - Parent labels are empty (0 messages) - wasted space?
- [ ] **Compare with Inbox Zero product structure:**
  - Inbox Zero uses 7 flat labels: To Reply, Awaiting Reply, FYI, Actioned, Newsletter, Marketing, Calendar, Receipt, Notification, Cold Email
  - Action-oriented: "To Reply" and "Awaiting Reply" make it to inbox
  - Archive after "Actioned"
  - ~7 labels might be optimal for inbox management
- [ ] **Decision criteria:**
  - If nested structure doesn't help navigation at 200 emails, migrate to flat
  - Nudge Experiment 3 toward action-oriented labels (To Reply, Actioned, FYI)
  - Consider Inbox Zero's proven structure (7 labels, action-based)
- **Status:** Testing at 200 emails to inform decision

### Classifier Improvements
- [x] **Label Consolidation:** Feed existing labels to classifier to encourage reuse ✅ SOLVED!
  - Solution implemented: Pass labels hash through pipeline
  - Results: 50 emails → 11 labels (Exp 1) vs 6 labels (Exp 3)
  - Experiment 3 wins: 45% fewer labels, better discrimination

### Advanced Features
- [ ] Filter conditions beyond LLM (sender whitelist, regex, etc.)
- [ ] Dry-run mode (show what would happen without doing it)
- [ ] Web UI for viewing logs/stats
- [ ] Email preview before applying actions
- [ ] Undo/revert actions

### Label System
- [x] **Simplified to flat labels:** Using `Receipt`, `Newsletter`, etc. (no `Schemail/` prefix)
  - Hidden `Schemail` marker label for "processed" queries
  - Both labels applied together: content label + marker
  - Benefits: Clean UI, easy colors, Inbox Zero aesthetic
  - See: notes/label-structure.md for design rationale

### Performance
- [ ] Parallel email processing (future/promises in Racket)
- [ ] Cache LLM responses (same email content = same classification)
- [ ] Batch LLM calls (send multiple emails at once)

### Config Improvements
- [ ] Support multiple config files (import/compose filters)
- [ ] Filter templates (reusable prompt fragments)
- [ ] Variables in prompts (e.g., `$from`, `$subject`)

---

## Current Status

**Phase:** Phase 2 & 3 Complete! 🚀 Now on Phase 4 (Daemon)

**What's Working:**
- ✅ OAuth with refresh tokens (persisted, encrypted)
- ✅ Gmail API wrapper (full CRUD on messages/labels)
- ✅ S-expression filter DSL with conditions and actions
- ✅ Automatic label creation
- ✅ **LLM Integration with Claude Sonnet 4.5 (Tool Calling)**
- ✅ **Agentic email processing - high-level instructions, model decides actions**
- ✅ **Dry-run mode for safe testing**
- ✅ **Tested successfully on real emails - 5/5 classified correctly!**

**Latest Achievement:**
Built complete agentic email filtering with Claude API:
- Tool calling approach (Approach 2 from notes/agentic.md)
- 5 tools: apply_label, archive_email, star_email, mark_as_read, do_nothing
- Cost: ~$0.006 per email (~$18/month for 100 emails/day)
- Successfully tested on Amazon, Anthropic, and GoDaddy notifications

**Next:** Build polling daemon (Phase 4) to automatically process new emails
