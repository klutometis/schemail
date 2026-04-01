# Self-Hosted vs. Unipile: Channel-by-Channel Analysis

Decision document for whether to use Unipile (hosted proxy) or
self-hosted open-source libraries for WhatsApp, LinkedIn, and
iMessage integration. This is orthogonal to the risk analysis in
`unified-messaging-risks.md` (which covers what happens *if* we use
Unipile). This document covers whether we *should*.

## Executive Summary

| Channel   | Recommendation                | Confidence |
|-----------|-------------------------------|------------|
| iMessage  | Self-hosted (BlueBubbles)     | High       |
| WhatsApp  | Self-hosted (Baileys)         | High       |
| LinkedIn  | Unipile (~$5.50/mo)           | High       |

iMessage and WhatsApp both have strong, actively maintained self-hosted
options that keep credentials and message content local. LinkedIn does
not — every open-source library is either dead, fragile, or requires
maintaining a Python/Playwright sidecar that LinkedIn actively works
to break.

## iMessage: BlueBubbles (self-hosted, Mac required)

**BlueBubblesApp/bluebubbles-server** — TypeScript, Apache-2.0.

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| GitHub stars           | 839                                        |
| Last commit            | May 16, 2025                               |
| Latest release         | v1.9.9 (May 16, 2025)                     |
| Protocol               | Reads macOS iMessage SQLite DB directly    |
| Browser required?      | No                                         |
| Auth method            | Shared password (query param)              |
| Runs as                | macOS app (Electron) exposing REST API     |
| Requires               | A Mac running macOS, always on             |

**How it works**: BlueBubbles is a macOS server app that reads
iMessage's local `chat.db` database (requires Full Disk Access) and
exposes it as a REST API + Socket.IO for realtime push. Clients
connect over HTTPS via built-in tunnel (ngrok/Cloudflare) or
port-forwarding with dynamic DNS.

There is no proxy/Unipile equivalent for iMessage. Apple's ecosystem
is completely closed. The only way to get programmatic iMessage access
is through a Mac running the Messages app. BlueBubbles is the most
mature open-source project for this.

### API surface (relevant to us)

| Need                  | Endpoint                              | Notes                    |
|-----------------------|---------------------------------------|--------------------------|
| List conversations    | `POST /api/v1/chat/query`             | Pagination + filters     |
| Get messages in chat  | `GET /api/v1/chat/:guid/message`      | Per-chat history         |
| Send reply            | `POST /api/v1/message/text`           | `chatGuid` + `message`   |
| Mark as read          | `POST /api/v1/chat/:guid/read`        | Requires Private API     |
| Webhooks              | `POST /api/v1/webhook`                | Push on new messages     |
| Send attachment       | `POST /api/v1/message/attachment`     |                          |
| Send reaction         | `POST /api/v1/message/react`          | Requires Private API     |

The API is comprehensive — also covers contacts, attachments,
scheduled messages, typing indicators, group chat management,
FindMy, and FaceTime. Far more than we need.

Authentication is a simple shared password passed as `?password=`
query parameter on every request. All connections use TLS.

### Private API

Some features (mark as read, reactions, typing indicators, edit/
unsend) require the "Private API" helper bundle, which injects into
the Messages app process. This requires **disabling SIP** (System
Integrity Protection) on the Mac. Trade-off: reduced security
hardening, but acceptable on a dedicated appliance Mac that does
nothing else.

### Hardware options

| Setup                        | Cost          | Notes                             |
|------------------------------|---------------|-----------------------------------|
| Old Mac Mini (2009-2014)     | $50-100 (eBay)| Patch to High Sierra. Basic features work. |
| Current Mac Mini (M-series)  | $500-600 new  | Full feature set. Ventura+ recommended. |
| Mac in a closet/garage       | $0 ongoing    | Home network + Cloudflare tunnel.  |
| Mac colocation               | ~$30-50/mo    | Overkill unless you need uptime guarantees. |
| macOS VM on Linux/Windows    | $0            | Technically possible (Apple hardware required for legal compliance). Documented in BlueBubbles guides. |

The canonical setup is a **Mac Mini as a dedicated headless
appliance**: always on, connected to home network, running BlueBubbles
and nothing else. Cloudflare tunnel or ngrok for remote access.

### macOS version compatibility

| macOS Version       | Feature coverage                          |
|---------------------|-------------------------------------------|
| High Sierra-Catalina| Send/receive, attachments, tapbacks. No replies UI, no edit/unsend. |
| Big Sur-Monterey    | Full messaging features. FindMy devices.  |
| Ventura+            | Everything including edit/unsend, mark unread. **Recommended.** |

### Risks and caveats

- **Requires a Mac, always on.** This is non-negotiable. There's no
  way around the hardware requirement.
- **Known stability issue.** Some users report the server needs
  rebooting every 3-4 days. Manageable with a cron watchdog or
  launchd plist, but not completely hands-off.
- **SIP must be disabled** for Private API features (mark read,
  reactions). Acceptable on a dedicated appliance, concerning if it's
  your daily driver Mac.
- **Last commit May 2025.** ~9 months without a commit as of
  Feb 2026. The project appears stable/mature rather than abandoned
  (v1.9.9 is a mature version number, 839 stars, no open issues
  shown). But worth monitoring.
- **No SMS support** currently (iMessage only, not green-bubble SMS).
- **Apple could break it** with a macOS update that changes how
  `chat.db` works or restricts Full Disk Access further. This has
  not happened in the project's multi-year history, but it's a risk.

### iMessage Verdict

**BlueBubbles is the only viable option**, and it's a good one:

1. **No alternative exists.** Apple's iMessage is completely closed.
   There is no Unipile-like proxy, no protocol library, no browser
   automation path. BlueBubbles (reading the local DB on a Mac) is
   it.
2. **The API is excellent.** Full REST API with websocket push,
   webhooks, comprehensive endpoint coverage. Better documented than
   most commercial APIs.
3. **Privacy is perfect.** Everything stays on your Mac. No third
   party ever sees your messages.
4. **Cost is low.** A used Mac Mini ($50-100) + electricity. No
   monthly fees.
5. **Integration is straightforward.** Same pattern as the other
   channels — Racket makes HTTP calls to a local/tunneled REST API.
   BlueBubbles *is* the shim; no wrapper process needed.

The only real cost is the Mac hardware and the commitment to keeping
it running. If you already have a spare Mac (or are willing to buy a
cheap used one), this is a no-brainer addition.

---

## WhatsApp Options

### Option 1: Baileys (self-hosted)

**WhiskeySockets/Baileys** — TypeScript/JavaScript, MIT license.

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| GitHub stars           | 8.3k                                       |
| Last commit            | Feb 11, 2026                               |
| Latest release         | v7.0.0-rc.9 (Nov 21, 2025)                |
| Maintainer             | Rajeh Taher (WhiskeySockets org)           |
| Protocol               | Direct WebSocket to WhatsApp servers       |
| Browser required?      | No — pure protocol, no Puppeteer/Selenium  |
| Auth method            | QR code scan (multi-device protocol)       |
| Runs as                | In-process Node.js library                 |

**How it works**: Connects directly to WhatsApp's servers via
WebSocket using the reverse-engineered multi-device protocol. Same
protocol that WhatsApp Web uses, but without a browser. Pairs via QR
code, occupies one of four linked-device slots.

**Capabilities relevant to us**:
- Read incoming messages (event-driven)
- Send messages to existing chats
- Archive chats
- Group metadata handling
- Label support (WhatsApp Business labels)

**Risks and caveats**:
- v7 introduced breaking changes; migration guide available at
  whiskey.so/migrate-latest.
- Known issue: accounts can get permanently banned when uploading
  status/stories via Baileys (not relevant to our read+reply use
  case).
- Group messaging without cached metadata triggers rate limits.
- Maintainer relies on sponsorship income; sustainability depends on
  continued funding.

**Integration with schemail-flow**: Requires a small Node.js shim
process that Racket communicates with via HTTP or stdin/stdout.
Baileys runs as an event-driven library, so the shim would expose a
simple REST API (list chats, get messages, send message, archive).

### Option 2: whatsapp-web.js (self-hosted)

**pedroslopez/whatsapp-web.js** — JavaScript, Apache-2.0 license.

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| GitHub stars           | 21.2k                                      |
| Last commit            | Feb 18, 2026                               |
| Latest release         | v1.34.6 (Jan 30, 2026)                    |
| Open issues            | 128                                        |
| Maintainer             | Pedro S. Lopez                             |
| Protocol               | Puppeteer-based browser automation         |
| Browser required?      | Yes — launches Chromium via Puppeteer       |
| Auth method            | QR code scan                               |
| Runs as                | In-process Node.js library + headless browser |

**How it works**: Automates WhatsApp Web inside a headless Chromium
browser via Puppeteer. Accesses WhatsApp Web's internal JavaScript
functions through the browser context.

**Capabilities**: Similar to Baileys — messages, media, groups,
reactions, status.

**Risks and caveats**:
- **Requires a running Chromium instance** — heavier resource
  footprint than Baileys (RAM, CPU).
- Significant stability issues reported: sessions stop receiving
  messages after 10-60 minutes, forced logouts, high CPU load after
  v1.31.0.
- Rate-limit issues with phone-number pairing.
- Browser-based approach means WhatsApp DOM changes can break it.

**Why Baileys is preferred over whatsapp-web.js for our use case**:
1. No browser dependency — lighter, more reliable for a daemon/TUI.
2. Direct protocol access is more stable than DOM scraping.
3. Lower detection surface — no Chromium fingerprint to analyze.
4. Lower resource usage (no headless browser process).

### Option 3: Unipile (hosted proxy)

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| Protocol               | QR code pairing (same multi-device protocol)|
| Browser required?      | No                                         |
| Auth method            | QR code via Unipile's hosted wizard        |
| Runs as                | REST API calls to Unipile's servers        |

**How it works**: Unipile acts as a linked device on your WhatsApp
account, same as Baileys. But the "device" runs on Unipile's servers
(Scaleway, France), and you interact via their REST API.

**Integration with schemail-flow**: Simplest option — just HTTP calls
from Racket. No Node.js sidecar needed.

### WhatsApp: Comparison Matrix

| Factor                      | Baileys            | whatsapp-web.js    | Unipile            |
|-----------------------------|--------------------|--------------------|--------------------| 
| Message content stays local | Yes                | Yes                | **No** (Unipile servers) |
| Credentials stay local      | Yes (auth state file) | Yes (session data) | **No** (Unipile servers) |
| Additional runtime          | Node.js shim       | Node.js + Chromium | None               |
| Monthly cost                | $0                 | $0                 | ~$5.50+            |
| Maintenance burden          | Medium (protocol breaks) | High (DOM + browser) | Low (Unipile maintains) |
| Detection risk              | Same as Unipile    | Slightly higher    | Same as Baileys    |
| Resource usage              | Low (event loop)   | High (Chromium)    | Zero (remote)      |
| Vendor dependency           | None               | None               | Full               |
| Setup complexity            | Medium (QR + shim) | Medium (QR + browser) | Low (QR via wizard) |
| Recovery from breakage      | Wait for library update or fix | Wait for library update | Wait for Unipile fix |

### WhatsApp Verdict

**Baileys is the clear winner for self-hosting**, and self-hosting is
preferred over Unipile for WhatsApp because:

1. **Privacy**: Messages and credentials never leave your machine.
   Unipile stores message content on their servers — for a personal
   messaging app, this is a meaningful difference.
2. **Cost**: $0 vs $5.50+/mo.
3. **Same protocol**: Both Baileys and Unipile use the multi-device
   protocol. The detection risk is equivalent. Unipile doesn't add
   safety — it's the same underlying mechanism, just hosted remotely.
4. **Acceptable maintenance**: Baileys is actively maintained (last
   commit 2 weeks ago) with 8.3k stars and a dedicated maintainer.
   WhatsApp protocol breaks happen but are typically fixed within
   days.

**The cost is one additional moving part**: a ~100-150 line Node.js
shim process that exposes Baileys as a local REST API for Racket to
call. This is a fair trade for keeping credentials local and saving
the monthly fee.

---

## LinkedIn Options

### Option 1: tomquirk/linkedin-api (Python, self-hosted)

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| PyPI version           | 2.3.1 (Nov 7, 2024)                       |
| Language               | Python (>= 3.10)                           |
| License                | MIT                                        |
| Maintainer             | Tom Quirk                                  |
| Protocol               | Direct HTTP to LinkedIn Voyager endpoints  |
| Browser required?      | No                                         |
| Auth method            | Username/password → cookie                 |

**How it works**: Authenticates to LinkedIn via username/password (or
cookies), then calls LinkedIn's internal Voyager REST endpoints
directly. Same endpoints that linkedin.com's frontend uses.

**Messaging support**: Can send and retrieve messages.

**Problems for our use case**:
- **Requires username/password authentication.** The library POSTs
  credentials to LinkedIn's auth endpoint. This is the auth method
  with the highest detection risk (see risks doc). LinkedIn's
  CHALLENGE mechanism frequently blocks these logins, especially from
  new IPs.
- **CHALLENGE problem is documented and unsolved.** The library's own
  troubleshooting says: "Linkedin will throw you a curve ball in the
  form of a Challenge URL. We currently don't handle this."
- **Python runtime required.** Our codebase is Racket. Using this
  means running a Python sidecar process.
- **GitHub repo returned 404** when scraped (Feb 2026), though PyPI
  still serves the package. Could be temporary or the repo going
  private — either way, a yellow flag for a core dependency.

**Notable**: Unipile is a sponsor of this project. The LinkedIn
self-hosted ecosystem is painful enough that the main open-source
library points users toward paid proxies.

### Option 2: eilonmore/linkedin-private-api (TypeScript, self-hosted)

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| GitHub stars           | 288                                        |
| Last commit            | Jul 14, 2022                               |
| Latest release         | v1.1.1 (Aug 7, 2021)                      |
| Language               | TypeScript                                 |
| License                | MIT                                        |
| Protocol               | Direct HTTP to LinkedIn Voyager endpoints  |

**Status: Effectively dead.** No commits in 3.5+ years. Last release
nearly 5 years ago. LinkedIn has changed their Voyager endpoints
multiple times since then. Almost certainly broken.

### Option 3: Playwright/Puppeteer DIY (self-hosted)

Roll your own LinkedIn messaging client by automating a real browser.

**How it would work**: Launch headless Chromium, log in with injected
cookies, navigate to linkedin.com/messaging, scrape DOM to read
messages, inject text to reply.

**Problems**:
- **LinkedIn actively detects headless browsers.** They fingerprint
  TLS handshakes, WebGL, Canvas, navigator properties. Stealth
  plugins exist but it's a cat-and-mouse game.
- **DOM changes constantly.** LinkedIn ships frontend updates
  frequently. Any selector-based scraping breaks regularly.
- **No open-source project does this reliably.** Nobody has published
  a maintained Playwright-based LinkedIn messaging tool — because the
  maintenance burden is too high for the community to sustain.
- **Session management is fragile.** LinkedIn detects multiple
  sessions, unusual IP patterns, and activity anomalies from
  automated browsers.

**Estimated maintenance burden**: 2-5 hours/month fixing selectors
and session issues. Possibly more during LinkedIn's major frontend
redesigns.

### Option 4: Unipile (hosted proxy)

| Attribute              | Value                                      |
|------------------------|--------------------------------------------|
| Cost                   | ~$5.50/mo per LinkedIn account             |
| Protocol               | Session cookies + residential proxies      |
| Browser required?      | No                                         |
| Auth method            | Cookie-based (hosted wizard or Chrome ext) |
| Runs as                | REST API calls to Unipile's servers        |

**How it works**: Unipile maintains your LinkedIn session on their
servers. They route requests through residential proxies geolocated
near your real IP. LinkedIn sees what looks like a normal browser
session.

**Why Unipile works where self-hosting doesn't**:
1. **Residential proxy infrastructure** — LinkedIn detects datacenter
   IPs and headless browser fingerprints. Unipile's residential
   proxies are designed to evade this. Building your own residential
   proxy setup is possible but adds serious operational complexity.
2. **They maintain the integration.** When LinkedIn changes endpoints
   or detection methods, Unipile fixes it. You don't maintain
   selectors or fight CHALLENGE flows.
3. **Cookie-based auth** — Unipile supports importing `li_at`/`li_a`
   cookies from your real browser session (via Chrome extension or
   manual paste). This avoids the username/password auth path
   entirely, which is safer than what `linkedin-api` offers.

### LinkedIn: Comparison Matrix

| Factor                      | linkedin-api (Py) | linkedin-private-api | Playwright DIY    | Unipile            |
|-----------------------------|--------------------|----------------------|-------------------|--------------------|
| Currently functional?       | Probably (w/ issues) | **No** (dead)      | DIY effort        | Yes                |
| Messaging support           | Yes                | Yes (was)            | Possible          | Yes                |
| Auth method                 | Username/password  | Username/password    | Cookies           | Cookies            |
| Additional runtime          | Python             | Node.js              | Node.js + Chromium| None               |
| Monthly cost                | $0                 | $0                   | $0                | ~$5.50             |
| Maintenance burden          | High (challenges)  | N/A (dead)           | Very high         | Low                |
| Detection risk              | Medium-high        | N/A                  | High              | Low-medium         |
| Residential proxy           | No (your IP)       | No                   | No (unless DIY)   | Yes (included)     |

### LinkedIn Verdict

**Unipile is the practical choice** for LinkedIn because:

1. **No viable self-hosted option exists.** The Python `linkedin-api`
   is the closest, but it requires username/password auth (risky),
   runs in Python (not our stack), has an unsolved CHALLENGE problem,
   and its GitHub repo is currently 404ing. `linkedin-private-api` is
   dead. Playwright DIY is a maintenance nightmare.
2. **LinkedIn actively fights automation.** Unlike WhatsApp (where the
   multi-device protocol is relatively stable and openly used by
   multiple clients), LinkedIn has no semi-official protocol. Every
   approach is fragile reverse-engineering. Paying Unipile ~$5.50/mo
   to maintain this is paying for their ongoing cat-and-mouse effort.
3. **The detection risk with Unipile is lower than self-hosting.**
   Unipile's residential proxies and session management reduce the
   fingerprinting signals that LinkedIn uses. Self-hosted approaches
   either expose your datacenter/home IP directly or require you to
   build your own proxy infrastructure.
4. **The price is right.** At ~$5.50/mo for a single LinkedIn account,
   the cost-benefit is heavily in favor of letting someone else deal
   with LinkedIn's hostility toward automation.

---

## The Hybrid Architecture

Based on the above analysis, the recommended approach is:

```
iMessage  →  BlueBubbles (Mac Mini + REST API)     →  schemail-flow
WhatsApp  →  Baileys (self-hosted Node.js shim)    →  schemail-flow
LinkedIn  →  Unipile (hosted REST API, ~$5.50/mo)  →  schemail-flow
Gmail     →  Gmail API (existing OAuth)             →  schemail-flow
```

### What this means for the codebase

Each channel gets its own thin Racket adapter module, all presenting
the same interface to the TUI and daemon (list-chats, get-messages,
send-message, archive, mark-read):

| Module                    | Purpose                              |
|---------------------------|--------------------------------------|
| `src/imessage.rkt`        | iMessage via BlueBubbles REST API    |
| `src/whatsapp.rkt`        | WhatsApp via local Baileys shim      |
| `src/unipile.rkt`         | LinkedIn only (Unipile REST API)     |
| `src/gmail.rkt`           | Gmail (existing, add thread funcs)   |
| `shim/whatsapp-server.js` | Node.js process wrapping Baileys     |

BlueBubbles doesn't need a shim — it *is* the server. Racket calls
its REST API directly (same as Unipile, just self-hosted).

### The Baileys shim

A minimal Express/Fastify HTTP server (~100-150 lines) that:

1. On startup: loads auth state from disk, connects to WhatsApp.
2. Exposes endpoints:
   - `GET /chats?unread=true` — list recent chats
   - `GET /chats/:id/messages?limit=10` — get messages
   - `POST /chats/:id/messages` — send reply
   - `PATCH /chats/:id` — archive, label, mark read
3. Stores auth state to disk (survives restarts without re-pairing).
4. Runs as a background process alongside schemail-flow/daemon.

### Infrastructure summary

| Component           | Runs on            | Always on? | Cost                  |
|---------------------|--------------------|------------|-----------------------|
| BlueBubbles server  | Mac Mini (garage)  | Yes        | ~$50-100 (one-time HW)|
| Baileys shim        | Primary machine    | Daemon: yes, flow: on-demand | $0 |
| Unipile             | Their servers      | Yes        | ~$5.50/mo             |
| Gmail API           | Google             | Yes        | $0                    |
| PostgreSQL          | Neon               | Yes (scale-to-zero) | $0 (free tier) |
| schemail-flow (TUI) | Primary machine    | On-demand  | $0                    |
| schemail (daemon)   | Primary machine    | Yes        | $0                    |

**Total recurring cost: ~$5.50/mo** (Unipile for LinkedIn only).

### Trade-offs of hybrid vs. Unipile-for-all-non-email

| Factor                  | Hybrid (recommended)       | Unipile for WA + LI       |
|-------------------------|----------------------------|----------------------------|
| iMessage                | **Supported** (BlueBubbles)| Not possible (no proxy exists) |
| WhatsApp privacy        | **Local**                  | Remote (Unipile servers)   |
| WhatsApp cost           | **$0**                     | ~$5.50/mo                  |
| LinkedIn cost           | ~$5.50/mo                  | ~$5.50/mo                  |
| Moving parts            | 4 (Racket + Node shim + BB + Unipile) | 2 (Racket + Unipile) |
| Integration patterns    | 2 (local HTTP + remote REST) | 1 (remote REST only)    |
| Maintenance burden      | Medium                     | Low                        |
| Vendor dependency       | LinkedIn only              | WA + LinkedIn              |
| Credential exposure     | LinkedIn session only      | WA + LinkedIn              |

---

## Open Questions

1. **Mac hardware**: Do you have a spare Mac already, or does one
   need to be acquired? A 2009-era Mac Mini on eBay ($50-100) works
   for basic features; an M-series Mac Mini ($500-600) gets the full
   Ventura+ feature set.

2. **BlueBubbles stability**: Need to test the reported "reboot
   every 3-4 days" issue firsthand. If real, set up a launchd plist
   or cron watchdog to restart BlueBubbles automatically.

3. **BlueBubbles Private API vs. standard**: Is mark-as-read
   important enough to justify disabling SIP? If the Mac is a
   dedicated appliance, probably yes. If it's a daily driver, no.

4. **Baileys auth state persistence**: How robust is the file-based
   auth state? Does it survive long periods of shim downtime, or does
   the WhatsApp device get unlinked after inactivity?

5. **Shim lifecycle management**: Should the Baileys shim be a
   systemd service, a Docker container, or just a process managed by
   schemail-flow? Depends on whether it needs to run continuously
   (daemon mode) or on-demand (flow mode only).

6. **Network topology for BlueBubbles**: Cloudflare tunnel (zero
   config, depends on Cloudflare) vs. ngrok (free tier, reconnects)
   vs. port-forwarding + dynamic DNS (fully self-hosted, more setup).

## Future Possibilities

These don't affect the core channel architecture but are natural
extensions once the four-channel foundation is in place:

1. **Web server + iPhone webview**: Wrap the same conversation
   operations (list, read, reply, archive) behind a small HTTP
   server. Racket has decent HTTP server libraries. The phone client
   would be a mobile-optimized web page loaded in Safari or an iOS
   webview wrapper — avoids the App Store entirely.

2. **Google Calendar integration**: Another Gmail API scope. Surface
   upcoming events in the TUI or as context for the AI reply drafter
   ("I'm free Tuesday afternoon").

3. **Auto-unsubscribe**: A classifier action that looks for
   `List-Unsubscribe` headers in email and automatically sends the
   unsubscribe request. Low risk, high quality-of-life improvement.
