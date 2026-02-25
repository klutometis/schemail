# Self-Hosted vs. Unipile: Channel-by-Channel Analysis

Decision document for whether to use Unipile (hosted proxy) or
self-hosted open-source libraries for WhatsApp and LinkedIn messaging
integration. This is orthogonal to the risk analysis in
`unified-messaging-risks.md` (which covers what happens *if* we use
Unipile). This document covers whether we *should*.

## Executive Summary

| Channel   | Recommendation         | Confidence |
|-----------|------------------------|------------|
| WhatsApp  | Self-hosted (Baileys)  | High       |
| LinkedIn  | Unipile                | High       |

WhatsApp has strong, actively maintained self-hosted options that keep
credentials and message content local. LinkedIn does not — every
open-source library is either dead, fragile, or requires maintaining
a Python/Playwright sidecar that LinkedIn actively works to break.

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
WhatsApp  →  Baileys (self-hosted Node.js shim)  →  schemail-flow
LinkedIn  →  Unipile (hosted REST API)            →  schemail-flow
Gmail     →  Gmail API (existing OAuth)           →  schemail-flow
```

### What this means for the codebase

Instead of a single `src/unipile.rkt` that handles both WhatsApp and
LinkedIn, we'd have:

| Module                    | Purpose                              |
|---------------------------|--------------------------------------|
| `src/unipile.rkt`         | LinkedIn only (Unipile REST API)     |
| `src/whatsapp.rkt`        | WhatsApp via local Baileys shim      |
| `shim/whatsapp-server.js` | Node.js process wrapping Baileys     |

Both `unipile.rkt` and `whatsapp.rkt` would present the same
interface to the TUI and daemon (list-chats, get-messages,
send-message, archive, label), just with different backends.

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

### Trade-offs of hybrid vs. Unipile-for-both

| Factor                  | Hybrid                     | Unipile for both          |
|-------------------------|----------------------------|---------------------------|
| WhatsApp privacy        | **Local**                  | Remote (Unipile servers)  |
| WhatsApp cost           | **$0**                     | ~$5.50/mo                 |
| LinkedIn cost           | ~$5.50/mo                  | ~$5.50/mo                 |
| Moving parts            | 3 (Racket + Node shim + Unipile) | 2 (Racket + Unipile) |
| Integration patterns    | 2 (local HTTP + remote REST) | 1 (remote REST only)   |
| Maintenance burden      | Medium (Baileys updates)   | Low (Unipile maintains)   |
| Vendor dependency       | LinkedIn only              | Both channels             |
| Credential exposure     | LinkedIn session only      | Both WA + LinkedIn        |

---

## Open Questions

1. **Baileys auth state persistence**: How robust is the file-based
   auth state? Does it survive long periods of shim downtime, or does
   the WhatsApp device get unlinked after inactivity?

2. **Shim lifecycle management**: Should the Baileys shim be a
   systemd service, a Docker container, or just a process managed by
   schemail-flow? Depends on whether it needs to run continuously
   (daemon mode) or on-demand (flow mode only).

3. **Unified messaging plan update**: If hybrid is confirmed, the
   main `unified-messaging.md` plan needs updating — split
   `src/unipile.rkt` scope, add `src/whatsapp.rkt` +
   `shim/whatsapp-server.js`, adjust architecture diagram.
