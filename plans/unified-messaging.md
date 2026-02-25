# Unified Messaging: WhatsApp + LinkedIn + Email

Extend schemail-flow from email-only triage to a unified
conversation-first flow across Gmail, WhatsApp, and LinkedIn.

## Motivation

schemail-flow works well for cranking through email inbox. WhatsApp and
LinkedIn messaging are equally painful (or worse) to triage manually.
Neither platform offers meaningful API access to end-users directly:

- **LinkedIn**: No messaging API for regular users. Only
  Recruiter/Partner-level access.
- **WhatsApp**: Business API requires a dedicated phone number (not
  personal). Personal-number access requires browser automation or a
  proxy service.

## Approach: Unipile as Unified Messaging Proxy

[Unipile](https://www.unipile.com/) provides a single REST API that
wraps LinkedIn and WhatsApp (and others) by maintaining authenticated
sessions on your behalf. One API key, one set of endpoints for both
platforms.

- **Authentication**: `X-API-KEY` header + per-tenant DSN base URL.
- **Account connection**: One-time browser flow via Unipile's hosted
  auth wizard. You log into LinkedIn/WhatsApp once; Unipile maintains
  the session.
- **Cost**: ~$50-200/mo depending on tier.
- **Risk**: See `plans/unified-messaging-risks.md` for deep dive.
  TL;DR: Low risk for reply-only use at low volume; not risk-free.

### Unipile API Surface (relevant endpoints)

```
GET  /api/v1/chats
     ?account_type=WHATSAPP|LINKEDIN
     &unread=true
     &limit=50
     &cursor=...
     → { object: "ChatList", items: [Chat, ...], cursor: "..." }

GET  /api/v1/chats/{chat_id}/messages
     ?limit=10
     → [Message, ...]

POST /api/v1/chats/{chat_id}/messages
     Content-Type: multipart/form-data
     text=Hello world
     → sends a message in existing chat

PATCH /api/v1/chats/{chat_id}
      Content-Type: application/json
      { "action": "setReadStatus|setArchiveStatus|setLabel|...", "value": ... }
      → modifies chat state
```

### Chat object (key fields)

```json
{
  "object": "Chat",
  "id": "unipile_id",
  "account_id": "connected_account_id",
  "account_type": "WHATSAPP|LINKEDIN",
  "provider_id": "native_platform_id",
  "name": "Contact or Group Name",
  "timestamp": "ISO 8601",
  "unread_count": 3,
  "archived": 0,
  "folder": ["INBOX", "INBOX_LINKEDIN_CLASSIC", ...]
}
```

### Message object (key fields)

```json
{
  "id": "unipile_message_id",
  "chat_id": "parent_chat_id",
  "provider_id": "native_message_id",
  "account_id": "connected_account_id",
  "text": "message body (plain text)",
  "sender_id": "provider user id",
  "timestamp": "ISO 8601",
  "is_sender": false,
  "seen": false
}
```

### PATCH chat actions by provider

| Action               | WhatsApp | LinkedIn |
|----------------------|----------|----------|
| `setReadStatus`      | yes      | yes      |
| `setArchiveStatus`   | yes      | no       |
| `setLabel`           | yes      | no       |
| `setMuteStatus`      | yes      | yes      |
| `setPinnedStatus`    | yes      | no       |

WhatsApp has near-parity with Gmail for our purposes (label + archive +
mark read). LinkedIn is read/unread only -- no native labels, no native
archive.

## Architecture

```
                    +----------------+
                    |   Supabase     |
                    |  PostgreSQL    |
                    | (state store)  |
                    +-------+--------+
                            |
             +--------------+--------------+
             |              |              |
      +------+------+ +----+----+  +------+------+
      |  schemail   | |schemail |  |   future    |
      |   daemon    | |  flow   |  |  mobile     |
      | (classify   | |  (TUI   |  |  client     |
      |  + label +  | |  triage |  |             |
      |  archive)   | | + reply)|  |             |
      +--+------+---+ +-+---+--+  +-------------+
         |      |      |   |
    +----+  +---+  +---+   +----+
    |       |      |            |
 +--+--+ +--+---+ +-+----+ +---+----+
 |Gmail| |Unipile| |Gmail | |Unipile |
 | API | | API   | | API  | |  API   |
 +-----+ +------+ +------+ +--------+
```

### Conversation-first model

The current schemail-flow iterates individual email messages. Gmail is
threaded too, and the flow doesn't leverage that. This redesign moves
to **one entry per conversation/thread** across all channels:

- **Gmail**: Use `gmail-list-threads` / `gmail-get-thread` instead of
  `gmail-list-messages` / `gmail-get-message`.
- **WhatsApp/LinkedIn**: One entry per Unipile chat.
- **Unified item**: All sources normalize to the same shape for the
  TUI loop.

Unified conversation item (internal hash):

```
source:        'email | 'whatsapp | 'linkedin
id:            thread-id (email) | chat-id (unipile)
display-from:  sender name / phone / LI name
subject:       email subject | chat name | sender name
last-text:     snippet or last message text
last-at:       timestamp (for sorting across sources)
raw:           the raw thread/chat hash (for operations)
history:       list of recent messages (for AI context)
```

In `all` mode, conversations from all sources are interleaved by
recency (most recent first) into one unified timeline.

## State Store: PostgreSQL on Supabase

Since LinkedIn has no native labels or archive, we maintain our own
state in PostgreSQL. This store is used for all channels (essential for
LinkedIn, supplementary for WhatsApp/Gmail which also apply native
actions).

Supabase is used purely as a free managed PostgreSQL instance. Connect
via standard wire protocol. Ignore everything else they offer.

### Schema

```sql
CREATE TABLE conversations (
    id                TEXT PRIMARY KEY,   -- "{provider}:{provider_id}"
    provider          TEXT NOT NULL,      -- "linkedin" | "whatsapp" | "gmail"
    provider_id       TEXT NOT NULL,      -- native ID from the platform
    unipile_id        TEXT,               -- Unipile's ID (null for gmail)
    name              TEXT,               -- contact/chat display name
    label             TEXT,               -- classifier result
    archived          BOOLEAN DEFAULT FALSE,
    rationale         TEXT,               -- LLM reasoning
    classified_at     TIMESTAMPTZ,
    last_message_id   TEXT,               -- most recent message we've processed
    last_message_text TEXT,               -- preview
    last_message_at   TIMESTAMPTZ
);

CREATE INDEX idx_conversations_provider ON conversations(provider);
CREATE INDEX idx_conversations_archived ON conversations(archived);
```

### How each channel uses the DB

| Channel   | DB role                                         |
|-----------|-------------------------------------------------|
| Gmail     | Supplementary record of classification results  |
| WhatsApp  | Supplementary (native labels/archive also used) |
| LinkedIn  | **Only source of truth** for label + archive     |

The `last_message_id` field tells the daemon whether a conversation has
new activity since it was last classified. If the current latest message
differs from the stored one, re-classify.

## Channel Capabilities Matrix

| Capability          | Gmail                  | WhatsApp              | LinkedIn         |
|---------------------|------------------------|-----------------------|------------------|
| Fetch conversations | `gmail-list-threads`   | Unipile list chats    | Unipile list chats |
| Classify (daemon)   | LLM -> label + archive | LLM -> label + archive| LLM -> label + archive |
| Native label        | Gmail label API        | `setLabel`            | **DB only**      |
| Native archive      | Remove INBOX label     | `setArchiveStatus`    | **DB only**      |
| Mark processed      | Hidden "Schemail" label| Mark as read          | **DB only** (last_message_id) |
| Reply (flow)        | `gmail-send-email`     | `unipile-send-message`| `unipile-send-message` |
| State in DB         | yes                    | yes                   | yes              |

### WhatsApp archive behavior note

Archived WhatsApp chats **unarchive themselves** when a new message
arrives (native WhatsApp behavior). The daemon will re-encounter and
re-process them, which is fine -- same as email arriving back in inbox.

## File Changes

### New files

| File                  | Purpose                                           |
|-----------------------|---------------------------------------------------|
| `src/unipile.rkt`     | Unipile REST API wrapper                          |
| `src/store.rkt`       | PostgreSQL state store (connection + CRUD)         |
| `config/unipile.rkt`  | Unipile config (provider selection, limits, etc.)  |

### Modified files

| File                      | Changes                                          |
|---------------------------|--------------------------------------------------|
| `bin/schemail-flow`       | `--source` flag. Conversation-first loop. Unified display with source badges. Source-aware send/archive. Reads state from DB. |
| `bin/schemail`            | `--source whatsapp` for daemon. Write state to DB for all sources. |
| `src/gmail.rkt`           | Add `gmail-list-threads`, `gmail-get-thread`.     |
| `src/reply-drafter.rkt`   | Add `#:history` param for conversation context.   |

## Detailed Module Specs

### src/unipile.rkt

```racket
;; Configuration from env vars:
;;   UNIPILE_API_KEY  -- API key from Unipile dashboard
;;   UNIPILE_DSN      -- e.g. "api1.unipile.com:13626"

;; Core functions:

(unipile-list-chats
  #:provider [provider #f]      ; "WHATSAPP" | "LINKEDIN" | #f for all
  #:unread-only? [unread? #t]
  #:limit [limit 50]
  #:cursor [cursor #f])
;; -> (hash 'items (list chat ...) 'cursor "...")

(unipile-get-chat-messages chat-id
  #:limit [limit 10])
;; -> list of messages, most recent first

(unipile-send-message chat-id text)
;; -> POST multipart/form-data, sends reply into chat

(unipile-patch-chat chat-id
  #:action action    ; "setReadStatus" | "setArchiveStatus" | "setLabel"
  #:value value)     ; boolean or string depending on action
;; -> PATCH chat state

(unipile-get-accounts)
;; -> list of connected accounts with provider type + account_id

;; Accessors:
(chat-id chat)           ; string
(chat-provider chat)     ; "WHATSAPP" | "LINKEDIN"
(chat-name chat)         ; display name
(chat-last-at chat)      ; timestamp string
(chat-unread-count chat) ; number
(message-text msg)       ; string
(message-sender msg)     ; sender_id string
(message-is-mine? msg)   ; boolean
(message-timestamp msg)  ; timestamp string
```

### src/store.rkt

```racket
;; Configuration from env vars:
;;   SCHEMAIL_DB_HOST
;;   SCHEMAIL_DB_PORT (default 5432)
;;   SCHEMAIL_DB_NAME
;;   SCHEMAIL_DB_USER
;;   SCHEMAIL_DB_PASSWORD
;;   SCHEMAIL_DB_SSL (default "yes")

;; Connection management:
(get-db-connection)          ; lazy singleton, reconnects if dropped
(ensure-schema!)             ; CREATE TABLE IF NOT EXISTS on startup

;; CRUD:
(store-conversation! conv)   ; upsert a conversation hash
(get-conversation id)        ; lookup by "{provider}:{provider_id}"
(list-conversations
  #:provider [provider #f]
  #:archived? [archived? #f]
  #:limit [limit 50])
;; -> list of conversation hashes

(update-conversation-label! id label rationale)
(update-conversation-archived! id archived?)
(conversation-needs-reclassify? id current-last-message-id)
;; -> #t if last_message_id differs from stored value
```

### src/gmail.rkt additions

```racket
(gmail-list-threads
  #:query [query #f]
  #:max-results [max-results 50]
  #:page-token [page-token #f])
;; -> (hash 'threads (list thread-stub ...) 'nextPageToken ...)
;; Uses: GET /users/me/threads?q=...&maxResults=...

(gmail-get-thread thread-id)
;; -> full thread hash with 'messages list (oldest first)
;; Uses: GET /users/me/threads/{id}?format=full
```

### src/reply-drafter.rkt changes

```racket
(draft-reply message-or-text
  #:user-email [user-email ""]
  #:user-name [user-name ""]
  #:thread-context [thread-context ""]
  #:history [history '()])       ; NEW: list of (hash 'sender S 'text T) pairs
;; When history is non-empty, injects a CONVERSATION HISTORY
;; section into the prompt with the last N exchanges for context.
```

### bin/schemail-flow changes

New `--source` CLI flag:

```
schemail-flow                    # default: email only
schemail-flow --source email
schemail-flow --source whatsapp
schemail-flow --source linkedin
schemail-flow --source all       # unified, interleaved by recency
```

Display changes:
- Source badge in header box: `[Email]` / `[WhatsApp]` / `[LinkedIn]`
- For chat-based sources: show last 3-5 messages as conversation
  snippet instead of single truncated body
- Actions remain: `[r]` reply, `[a]` archive/done, `[s]` skip, `[q]` quit

Send/archive dispatch:
- Email: `gmail-send-email` + remove INBOX label (existing)
- WhatsApp: `unipile-send-message` + `setArchiveStatus` + `setLabel`
- LinkedIn: `unipile-send-message` + update DB (archived, label)
- All channels: write/update conversation record in DB

### bin/schemail daemon changes

New `--source` flag for daemon mode:

```
schemail daemon --source email      # existing behavior
schemail daemon --source whatsapp   # new
schemail daemon --source all        # both
```

WhatsApp daemon loop:
1. Fetch unread WhatsApp chats via Unipile
2. For each: check DB `last_message_id` to see if already processed
3. Get last N messages for context
4. Classify with LLM (same prompt + schema as email)
5. Apply: `setLabel` (native WA label) + `setArchiveStatus` if
   should_archive + `setReadStatus` to mark processed
6. Write classification state to DB

LinkedIn daemon: not implemented. LinkedIn has nowhere to put the
result natively, and the DB-only state is better served by JIT
classification in schemail-flow. Can revisit later.

## Implementation Order

1. `src/store.rkt` -- DB connection + schema + CRUD
2. `src/unipile.rkt` -- API wrapper
3. `src/gmail.rkt` -- add thread-level functions
4. `src/reply-drafter.rkt` -- add `#:history` param
5. `bin/schemail-flow` -- unified conversation-first TUI
6. `bin/schemail` daemon -- WhatsApp mode + write-to-DB for all

## One-Time Setup (manual steps)

1. **Supabase**: Create project, get PostgreSQL connection string.
   Set env vars: `SCHEMAIL_DB_HOST`, `SCHEMAIL_DB_PORT`,
   `SCHEMAIL_DB_NAME`, `SCHEMAIL_DB_USER`, `SCHEMAIL_DB_PASSWORD`.

2. **Unipile**: Sign up, get API key + DSN. Set env vars:
   `UNIPILE_API_KEY`, `UNIPILE_DSN`.

3. **Connect accounts**: Visit Unipile's hosted auth wizard URL to
   connect your personal WhatsApp and LinkedIn accounts.

4. **Test**: Run `schemail-flow --source whatsapp` to verify.

## What Does NOT Change

- The automated email classifier daemon (`bin/schemail` in email mode)
- The label/color system (`src/label-colors.rkt`, `src/colors.rkt`)
- OAuth/Gmail auth (`src/oauth.rkt`)
- Filter DSL (`src/filters.rkt`)
- The `bin/classify` convenience wrapper
