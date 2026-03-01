# Unified Messaging: iMessage + WhatsApp + LinkedIn + Email

Extend schemail-flow from email-only triage to a unified
conversation-first flow across iMessage, Gmail, WhatsApp, and
LinkedIn.

## Motivation

schemail-flow works well for cranking through email inbox. WhatsApp,
LinkedIn, and iMessage are equally painful (or worse) to triage
manually. None offer meaningful API access to end-users directly:

- **iMessage**: Completely closed ecosystem. No API whatsoever.
  Only accessible by reading the local SQLite DB on a Mac.
- **LinkedIn**: No messaging API for regular users. Only
  Recruiter/Partner-level access.
- **WhatsApp**: Business API requires a dedicated phone number (not
  personal). Personal-number access requires browser automation or a
  proxy service.

## Approach: Hybrid (self-hosted + Unipile)

See `plans/self-hosted-vs-unipile.md` for the full channel-by-channel
analysis. Summary:

| Channel   | Backend                          | Cost          |
|-----------|----------------------------------|---------------|
| iMessage  | BlueBubbles (Mac Mini, REST API) | ~$50-100 HW   |
| WhatsApp  | Baileys (Node.js shim, local)    | $0             |
| LinkedIn  | Unipile (hosted REST API)        | ~$5.50/mo      |
| Gmail     | Gmail API (existing OAuth)       | $0             |

Three channels are fully self-hosted (credentials and messages stay
local). LinkedIn alone uses Unipile because there is no viable
self-hosted option — see the analysis doc for details.

### Unipile (LinkedIn only)

[Unipile](https://www.unipile.com/) provides a REST API that wraps
LinkedIn by maintaining an authenticated session on your behalf.

- **Authentication**: `X-API-KEY` header + per-tenant DSN base URL.
- **Account connection**: One-time browser flow via Unipile's hosted
  auth wizard, or cookie import via Chrome extension.
- **Cost**: ~$5.50/mo per LinkedIn account.
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
          |   daemon    | |  flow   |  |   web UI    |
          | (classify   | |  (TUI   |  |  (+ iPhone  |
          |  + label +  | |  triage |  |   webview)  |
          |  archive)   | | + reply)|  |             |
          +--+--+--+--+-+ +--+--+--+-+ +-------------+
             |  |  |  |     |  |  |  |
        +----+  |  |  +--+--+  |  |  +----+
        |       |  |     |     |  |        |
     +--+--+ +-+-+ +-+--+-+ +-+--+-+ +----+---+
     |Gmail| |BB | |Baileys| |Gmail | |Unipile |
     | API | |API| | shim  | | API  | |  API   |
     +-----+ +--++ +-------+ +------+ +--------+
                |
          +-----+------+
          | Mac Mini   |
          | BlueBubbles|
          | (iMessage) |
          +------------+

BB = BlueBubbles (iMessage, self-hosted on Mac Mini)
Baileys shim = WhatsApp (self-hosted Node.js process)
Unipile = LinkedIn only (~$5.50/mo)
```

### Conversation-first model

The current schemail-flow iterates individual email messages. Gmail is
threaded too, and the flow doesn't leverage that. This redesign moves
to **one entry per conversation/thread** across all channels:

- **Gmail**: Use `gmail-list-threads` / `gmail-get-thread` instead of
  `gmail-list-messages` / `gmail-get-message`.
- **iMessage**: One entry per BlueBubbles chat.
- **WhatsApp**: One entry per Baileys chat.
- **LinkedIn**: One entry per Unipile chat.
- **Unified item**: All sources normalize to the same shape for the
  TUI loop.

Unified conversation item (internal hash):

```
source:        'email | 'imessage | 'whatsapp | 'linkedin
id:            thread-id (email) | chat-guid (BB) | chat-id (WA/LI)
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
    provider          TEXT NOT NULL,      -- "imessage" | "linkedin" | "whatsapp" | "gmail"
    provider_id       TEXT NOT NULL,      -- native ID from the platform
    external_id       TEXT,               -- Unipile ID (LinkedIn) or BlueBubbles GUID (iMessage)
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
| iMessage  | **Primary** (iMessage has no native label/archive API) |
| WhatsApp  | Supplementary (native labels/archive also used) |
| LinkedIn  | **Only source of truth** for label + archive     |

The `last_message_id` field tells the daemon whether a conversation has
new activity since it was last classified. If the current latest message
differs from the stored one, re-classify.

## Channel Capabilities Matrix

| Capability          | Gmail                  | iMessage                | WhatsApp              | LinkedIn         |
|---------------------|------------------------|-------------------------|-----------------------|------------------|
| Fetch conversations | `gmail-list-threads`   | BB `chat/query`         | Baileys event-driven  | Unipile list chats |
| Classify (daemon)   | LLM -> label + archive | LLM -> label + archive  | LLM -> label + archive| LLM -> label + archive |
| Native label        | Gmail label API        | **DB only**             | `setLabel`            | **DB only**      |
| Native archive      | Remove INBOX label     | **DB only**             | `setArchiveStatus`    | **DB only**      |
| Mark processed      | Hidden "Schemail" label| BB `chat/:guid/read` (Private API) | Mark as read | **DB only** (last_message_id) |
| Reply (flow)        | `gmail-send-email`     | BB `message/text`       | Baileys `sendMessage` | `unipile-send-message` |
| State in DB         | yes                    | yes                     | yes                   | yes              |

### WhatsApp archive behavior note

Archived WhatsApp chats **unarchive themselves** when a new message
arrives (native WhatsApp behavior). The daemon will re-encounter and
re-process them, which is fine -- same as email arriving back in inbox.

## File Changes

### New files

| File                      | Purpose                                          |
|---------------------------|--------------------------------------------------|
| `src/imessage.rkt`        | BlueBubbles REST API wrapper (iMessage)          |
| `src/whatsapp.rkt`        | Baileys shim HTTP client (WhatsApp)              |
| `src/unipile.rkt`         | Unipile REST API wrapper (LinkedIn only)         |
| `src/store.rkt`           | PostgreSQL state store (connection + CRUD)        |
| `shim/whatsapp-server.js` | Node.js process wrapping Baileys as local REST   |
| `shim/package.json`       | Dependencies for the Baileys shim                |

### Modified files

| File                      | Changes                                          |
|---------------------------|--------------------------------------------------|
| `bin/schemail-flow`       | `--source` flag. Conversation-first loop. Unified display with source badges. Source-aware send/archive. Reads state from DB. |
| `bin/schemail`            | `--source` flag for daemon. Write state to DB for all sources. |
| `src/gmail.rkt`           | Add `gmail-list-threads`, `gmail-get-thread`.    |
| `src/reply-drafter.rkt`   | Add `#:history` param for conversation context.  |

## Detailed Module Specs

### src/imessage.rkt

```racket
;; Configuration from env vars:
;;   BLUEBUBBLES_URL       -- e.g. "https://xxxxx.ngrok.io" or local
;;   BLUEBUBBLES_PASSWORD  -- server password

;; Core functions (same interface as other channel modules):

(imessage-list-chats
  #:limit [limit 50])
;; -> list of chat hashes
;; Uses: POST /api/v1/chat/query

(imessage-get-chat-messages chat-guid
  #:limit [limit 10])
;; -> list of messages, most recent first
;; Uses: GET /api/v1/chat/:guid/message

(imessage-send-message chat-guid text)
;; -> sends reply into chat
;; Uses: POST /api/v1/message/text

(imessage-mark-read chat-guid)
;; -> marks chat as read (requires Private API on server)
;; Uses: POST /api/v1/chat/:guid/read
```

### src/whatsapp.rkt

```racket
;; Configuration from env vars:
;;   WHATSAPP_SHIM_URL  -- e.g. "http://localhost:3100"

;; Core functions (same interface as other channel modules):

(whatsapp-list-chats
  #:unread-only? [unread? #t]
  #:limit [limit 50])
;; -> list of chat hashes
;; Uses: GET /chats on local Baileys shim

(whatsapp-get-chat-messages chat-id
  #:limit [limit 10])
;; -> list of messages, most recent first
;; Uses: GET /chats/:id/messages on local shim

(whatsapp-send-message chat-id text)
;; -> sends reply into chat
;; Uses: POST /chats/:id/messages on local shim

(whatsapp-patch-chat chat-id
  #:action action    ; "archive" | "label" | "markRead"
  #:value value)
;; -> modifies chat state
;; Uses: PATCH /chats/:id on local shim
```

### src/unipile.rkt (LinkedIn only)

```racket
;; Configuration from env vars:
;;   UNIPILE_API_KEY  -- API key from Unipile dashboard
;;   UNIPILE_DSN      -- e.g. "api1.unipile.com:13626"

;; Core functions:

(unipile-list-chats
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
  #:action action    ; "setReadStatus" | "setMuteStatus"
  #:value value)     ; boolean
;; -> PATCH chat state (LinkedIn only supports read + mute)

(unipile-get-accounts)
;; -> list of connected accounts with provider type + account_id
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
schemail-flow --source imessage
schemail-flow --source whatsapp
schemail-flow --source linkedin
schemail-flow --source all       # unified, interleaved by recency
```

Display changes:
- Source badge in header box: `[Email]` / `[iMessage]` / `[WhatsApp]`
  / `[LinkedIn]`
- For chat-based sources: show last 3-5 messages as conversation
  snippet instead of single truncated body
- Actions remain: `[r]` reply, `[a]` archive/done, `[s]` skip, `[q]` quit

Send/archive dispatch:
- Email: `gmail-send-email` + remove INBOX label (existing)
- iMessage: `imessage-send-message` + `imessage-mark-read` + DB
- WhatsApp: `whatsapp-send-message` + archive + label via shim
- LinkedIn: `unipile-send-message` + update DB (archived, label)
- All channels: write/update conversation record in DB

### bin/schemail daemon changes

New `--source` flag for daemon mode:

```
schemail daemon --source email      # existing behavior
schemail daemon --source imessage   # new
schemail daemon --source whatsapp   # new
schemail daemon --source all        # all four channels
```

Generic daemon loop (same for all channels):
1. Fetch unread/recent conversations via channel adapter
2. For each: check DB `last_message_id` to see if already processed
3. Get last N messages for context
4. Classify with LLM (same prompt + schema as email)
5. Apply native actions where supported (labels, archive, mark read)
6. Write classification state to DB

Channel-specific daemon notes:
- **Email**: Existing behavior, unchanged.
- **iMessage**: Fetch via BlueBubbles, classify, mark read (Private
  API), store label/archive state in DB (no native label support).
- **WhatsApp**: Fetch via Baileys shim, classify, apply native
  `setLabel` + `setArchiveStatus` + `setReadStatus`, store in DB.
- **LinkedIn**: Fetch via Unipile, classify, mark read only (no
  native label/archive). All state goes to DB. Consider whether
  daemon is worthwhile here or if JIT classification in schemail-flow
  is sufficient.

## Implementation Order

1. `src/store.rkt` -- DB connection + schema + CRUD
2. `src/gmail.rkt` -- add thread-level functions
3. `src/reply-drafter.rkt` -- add `#:history` param
4. `src/imessage.rkt` -- BlueBubbles REST API wrapper
5. `shim/whatsapp-server.js` -- Baileys Node.js shim
6. `src/whatsapp.rkt` -- Baileys shim HTTP client
7. `src/unipile.rkt` -- Unipile REST API wrapper (LinkedIn)
8. `bin/schemail-flow` -- unified conversation-first TUI
9. `bin/schemail` daemon -- multi-source + write-to-DB for all

## One-Time Setup (manual steps)

1. **Supabase**: Create project, get PostgreSQL connection string.
   Set env vars: `SCHEMAIL_DB_HOST`, `SCHEMAIL_DB_PORT`,
   `SCHEMAIL_DB_NAME`, `SCHEMAIL_DB_USER`, `SCHEMAIL_DB_PASSWORD`.

2. **BlueBubbles (iMessage)**: Set up Mac Mini with BlueBubbles
   server. Sign into iMessage. Optionally install Private API bundle
   (requires disabling SIP). Set up Cloudflare tunnel or ngrok.
   Set env vars: `BLUEBUBBLES_URL`, `BLUEBUBBLES_PASSWORD`.

3. **Baileys shim (WhatsApp)**: `cd shim && npm install`. Run
   `node whatsapp-server.js`, scan QR code with phone. Auth state
   persists to disk. Set env var: `WHATSAPP_SHIM_URL`.

4. **Unipile (LinkedIn)**: Sign up, get API key + DSN. Connect
   LinkedIn account via hosted auth wizard (cookie-based auth
   recommended). Set env vars: `UNIPILE_API_KEY`, `UNIPILE_DSN`.

5. **Test each channel**:
   - `schemail-flow --source imessage`
   - `schemail-flow --source whatsapp`
   - `schemail-flow --source linkedin`
   - `schemail-flow --source all`

## What Does NOT Change

- The automated email classifier daemon (`bin/schemail` in email mode)
- The label/color system (`src/label-colors.rkt`, `src/colors.rkt`)
- OAuth/Gmail auth (`src/oauth.rkt`)
- Filter DSL (`src/filters.rkt`)
- The `bin/classify` convenience wrapper

## Future Possibilities

These don't block the core implementation but are natural extensions:

1. **Web server + iPhone webview**: Wrap the conversation operations
   behind a small Racket HTTP server. The phone client would be a
   mobile-optimized web page in Safari or an iOS webview wrapper —
   avoids the App Store entirely.

2. **Google Calendar integration**: Another Gmail API scope. Surface
   upcoming events as context for the AI reply drafter.

3. **Auto-unsubscribe**: A classifier action that detects
   `List-Unsubscribe` headers and sends the unsubscribe request
   automatically.
