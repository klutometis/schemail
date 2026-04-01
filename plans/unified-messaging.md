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
                        |     Neon       |
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

Unified conversation hash (internal representation):

```racket
(hash 'source          'whatsapp       ; 'gmail | 'whatsapp | 'imessage | 'linkedin
      'id              "whatsapp:5551234@s.whatsapp.net"  ; "{provider}:{native_id}"
      'from            "Alice Smith"   ; display name of sender / contact
      'subject         "Alice Smith"   ; email subject | chat name
      'body            "hey are you free?"  ; latest message text
      'last-at         1709500000      ; epoch seconds (for sorting across sources)
      'last-message-id "BAQE1234..."   ; native message ID (freshness check)
      'history         (list           ; recent messages, newest first
                         (hash 'sender "Alice" 'text "hey are you free?" 'at 1709500000)
                         (hash 'sender "You"   'text "maybe, when?"      'at 1709499000))
      'raw             <provider-hash>) ; original API response (escape hatch)
```

Every channel adapter normalizes its raw API data into this shape.
The core loop, reply drafter, TUI display, and DB store all work
exclusively off the top-level keys. The `'raw` field is an escape
hatch for the per-channel send/archive adapters that need
provider-specific fields (e.g. Gmail's `threadId` for threading,
WhatsApp's native chat JID for archiving).

**Who uses what**:

| Component              | Reads from unified hash                    | Touches `'raw`? |
|------------------------|--------------------------------------------|-----------------|
| `draft-reply`          | `from`, `subject`, `body`, `history`       | No              |
| TUI display            | `source`, `from`, `subject`, `body`, `history`, `last-at` | No |
| `store.rkt` (DB write) | `id`, `source`, `from`, `last-message-id`, `last-at` | No |
| Send reply             | `id`, `source`                             | **Yes** (threading, native IDs) |
| After-triage           | `id`, `source`                             | **Yes** (native archive/label/mark-read) |

**Native message IDs by channel** (none need fabrication):

| Channel   | Native message ID source            |
|-----------|-------------------------------------|
| Gmail     | `msg.id` (e.g. `18d3f2a1b4c`)      |
| WhatsApp  | Baileys `key.id` per message        |
| iMessage  | BlueBubbles message GUID            |
| LinkedIn  | Unipile `message.id`                |

In `all` mode, conversations from all sources are interleaved by
recency (most recent first) into one unified timeline.

## State Store: PostgreSQL on Neon

Since LinkedIn has no native labels or archive, we maintain our own
state in PostgreSQL. This store is used for all channels (essential for
LinkedIn, supplementary for WhatsApp/Gmail which also apply native
actions).

Neon is a serverless Postgres provider with a free tier (0.5GB storage,
100 compute-hours/mo). The database scales to zero when idle and wakes
automatically on connection (~0.5s cold start). SSL is enforced by
default. We connect via the pooler endpoint (PgBouncer) using a single
connection string.

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
| `src/reply-drafter.rkt`   | Refactor to accept unified hash (from, subject, body, history, source). |

## Adapter Contract

Every channel module exports the same three-function interface. The
core loop in `schemail-flow` and the daemon never touch provider-
specific data — they work exclusively through this contract.

```racket
;; Return a list of unified conversation hashes (see spec above).
;; Each adapter fetches from its provider API, then normalizes.
(channel-list-conversations
  #:limit [limit 50])
;; -> (listof unified-conversation-hash)

;; Send a text reply into the conversation.
;; Uses 'raw from the unified hash for provider-specific IDs
;; (e.g. Gmail threadId, WhatsApp JID).
(channel-send-message conv text)
;; -> void

;; Apply native post-triage side effects.
;; action is 'archive | 'mark-read | 'mute
;; Each adapter does what its platform supports; no-ops for the rest.
(channel-after-triage! conv action)
;; -> void
```

After-triage side effects by channel:

| Action       | Gmail                    | WhatsApp              | iMessage             | LinkedIn       |
|--------------|--------------------------|-----------------------|----------------------|----------------|
| `'archive`   | Remove INBOX label       | `setArchiveStatus`    | DB only              | DB only        |
| `'mark-read` | Remove UNREAD label      | `markRead`            | BB Private API       | `setReadStatus`|
| `'mute`      | N/A                      | `setMuteStatus`       | N/A                  | `setMuteStatus`|

The DB write (`store-conversation!`) happens in the **caller** (the
core loop), not in the adapter. The adapter only handles native
platform side effects.

## Detailed Module Specs

### src/store.rkt

```racket
;; Configuration from env vars:
;;   SCHEMAIL_DATABASE_URL  -- Neon pooler connection string
;;     e.g. "postgresql://user:pass@ep-xxx-pooler.region.aws.neon.tech/neondb?sslmode=require"

;; Parses the connection URL into components (Racket's db library
;; doesn't support URL strings natively). Uses virtual-connection +
;; connection-pool for Neon's scale-to-zero wake behavior.

;; Connection management:
(get-db-connection)          ; lazy singleton via virtual-connection
(ensure-schema!)             ; CREATE TABLE IF NOT EXISTS on startup

;; CRUD (all operate on unified conversation hashes):
(store-conversation! conv)   ; upsert from unified hash
(get-conversation id)        ; lookup by "provider:native_id"
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

### src/whatsapp.rkt

```racket
;; Configuration from env vars:
;;   WHATSAPP_SHIM_URL  -- e.g. "http://localhost:3100"

;; Implements the adapter contract for WhatsApp via local Baileys shim.

(whatsapp-list-conversations
  #:limit [limit 50])
;; -> (listof unified-conversation-hash)
;; Fetches from GET /chats on shim, normalizes each chat into
;; the unified shape (with history from GET /chats/:id/messages).

(whatsapp-send-message conv text)
;; -> POST /chats/:id/messages on shim
;; Extracts native chat JID from conv's 'raw field.

(whatsapp-after-triage! conv action)
;; -> PATCH /chats/:id on shim (archive, markRead, mute)
```

### shim/whatsapp-server.js

Minimal Express HTTP server (~100-150 lines) wrapping Baileys:

```
GET  /chats?unread=true&limit=50   -- list recent chats
GET  /chats/:id/messages?limit=10  -- get messages for a chat
POST /chats/:id/messages           -- send reply { text: "..." }
PATCH /chats/:id                   -- { action, value }
GET  /health                       -- connection status
```

On startup: loads auth state from `shim/auth_info/`, connects to
WhatsApp, prints QR code for first-time pairing. Auth state persists
across restarts. Uses Baileys' in-memory message store to serve
`GET /chats/:id/messages`.

### src/imessage.rkt (later)

```racket
;; Configuration from env vars:
;;   BLUEBUBBLES_URL       -- e.g. "https://xxxxx.ngrok.io"
;;   BLUEBUBBLES_PASSWORD  -- server password

(imessage-list-conversations #:limit [limit 50])
;; -> (listof unified-conversation-hash)

(imessage-send-message conv text)
(imessage-after-triage! conv action)
```

### src/unipile.rkt (later, LinkedIn only)

```racket
;; Configuration from env vars:
;;   UNIPILE_API_KEY  -- API key from Unipile dashboard
;;   UNIPILE_DSN      -- e.g. "api1.unipile.com:13626"

(unipile-list-conversations #:limit [limit 50])
;; -> (listof unified-conversation-hash)

(unipile-send-message conv text)
(unipile-after-triage! conv action)
```

### src/gmail.rkt additions

```racket
;; New thread-level functions:
(gmail-list-threads
  #:query [query #f]
  #:max-results [max-results 50]
  #:page-token [page-token #f])
;; -> (hash 'threads (list thread-stub ...) 'nextPageToken ...)

(gmail-get-thread thread-id)
;; -> full thread hash with 'messages list

;; Adapter contract implementation:
(gmail-list-conversations #:limit [limit 50])
;; -> (listof unified-conversation-hash)
;; Wraps gmail-list-threads + gmail-get-thread, normalizes.

(gmail-send-message conv text)
;; Extracts threadId, msg-id from conv's 'raw for proper threading.

(gmail-after-triage! conv action)
;; Removes INBOX/UNREAD labels as appropriate.
```

### src/reply-drafter.rkt changes

```racket
(draft-reply conv
  #:user-email [user-email ""]
  #:user-name [user-name ""])
;; Takes a unified conversation hash. Reads 'from, 'subject, 'body,
;; 'history, and 'source directly from it. The 'source field
;; calibrates tone: formal for 'gmail, casual for chat sources.
;;
;; No longer calls Gmail-specific helpers (message-from, get-email-body).
;; Those move to the Gmail adapter's normalization step.
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

The `--source` flag selects which adapter(s) to call. The core loop
is source-agnostic — it only sees unified conversation hashes:

```racket
(define convs (adapter-list-conversations source))  ; unified hashes
(for ([conv convs] [i (in-naturals 1)])
  (display-conversation conv i (length convs))      ; source badge + body/history
  (case (read-key)
    [(#\r) (define draft (draft-reply conv ...))
           (adapter-send-message conv draft)
           (adapter-after-triage! conv 'mark-read)
           (store-conversation! conv)]
    [(#\a) (adapter-after-triage! conv 'archive)
           (store-conversation! conv)]
    [(#\s) (void)]
    [(#\q) (exit 0)]))
```

Display changes:
- Source badge in header: `[Email]` / `[iMessage]` / `[WhatsApp]`
  / `[LinkedIn]`
- Chat sources: show last 3-5 messages as conversation snippet
- Actions: `[r]` reply, `[a]` archive/done, `[s]` skip, `[q]` quit

`adapter-send-message` and `adapter-after-triage!` dispatch to the
right channel module based on `(hash-ref conv 'source)`. Native side
effects (Gmail labels, WhatsApp archive, etc.) happen inside the
adapter. The DB write happens in the caller — always, for all sources.

### bin/schemail daemon changes

Same `--source` flag. Same adapter contract. One generic loop:

```
schemail daemon --source all        # all four channels
```

1. Fetch conversations via `adapter-list-conversations`
2. For each: check DB — `(conversation-needs-reclassify? id last-message-id)`
3. If new activity: classify with LLM (same prompt for all sources)
4. `adapter-after-triage!` for native side effects
5. `store-conversation!` to write label + archived state to DB

## Implementation Order

WhatsApp first (end-to-end), then add other channels:

1. `src/store.rkt` -- DB connection + schema + CRUD (Neon)
2. `shim/whatsapp-server.js` + `shim/package.json` -- Baileys Node.js shim
3. `src/whatsapp.rkt` -- adapter (list-conversations, send, after-triage!)
4. `src/reply-drafter.rkt` -- refactor to accept unified hash
5. `bin/schemail-flow` -- add `--source` flag, unified loop
6. (Later) `src/gmail.rkt` -- add thread funcs + adapter contract
7. (Later) `src/imessage.rkt` -- BlueBubbles adapter
8. (Later) `src/unipile.rkt` -- LinkedIn adapter
9. (Later) `bin/schemail` daemon -- multi-source classification

## One-Time Setup (manual steps)

1. **Neon**: Create project (free tier), copy the pooler connection
   string. Store as `SCHEMAIL_DATABASE_URL` in `~/.env-secrets`.

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
