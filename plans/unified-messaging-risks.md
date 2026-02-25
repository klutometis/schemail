# Risk Analysis: Unipile, Account Bans, and Platform ToS

Addendum to `plans/unified-messaging.md`.

Deep dive into the risks of using Unipile as a proxy for LinkedIn and
WhatsApp messaging, specifically for the use case of **responding to
incoming messages** (not cold outreach).

## How Unipile Actually Works (technical mechanism)

Unipile is not an official API partner of LinkedIn or WhatsApp. It
maintains access to these platforms by impersonating a regular user
session. The technical details:

### LinkedIn

- You provide your LinkedIn credentials (username/password) or
  session cookies (`li_a`, `li_at`) to Unipile.
- Unipile maintains your authenticated session on their servers.
- API calls go from Unipile's infrastructure through **residential
  proxies** (they auto-assign a fixed proxy geolocated near your
  IP) to LinkedIn's servers.
- LinkedIn sees what looks like a normal browser session from a
  residential IP -- not a datacenter. This is the core of how they
  avoid detection.
- If LinkedIn detects the separate session, it may show a "multiple
  sessions" warning and ask you to choose which to keep. This is
  recoverable (reconnect in Unipile), not a ban.
- Unipile also supports a Chrome extension approach where cookies
  are silently harvested from your real browser session and forwarded
  to Unipile, avoiding the dual-session problem entirely.

### WhatsApp

- Uses the **WhatsApp Web multi-device protocol** (QR code pairing).
- You scan a QR code with your phone, exactly like linking WhatsApp
  Web or WhatsApp Desktop.
- Unipile then acts as a "linked device" on your account.
- WhatsApp allows up to 4 linked devices. Unipile occupies one slot.
- Requests are routed through Unipile's servers with proxies, same
  as LinkedIn.

### Key implication

In both cases, Unipile has your session credentials stored on their
servers. If Unipile is compromised, your LinkedIn and WhatsApp
accounts are exposed.

---

## Unipile: Company Profile

- **Founded**: 2020, headquartered in Riorges (near Lyon), France.
- **Funding**: ~$1.6M seed round (March 2023) from Bpifrance + angel
  investors. No subsequent rounds reported.
- **Team size**: 1-11 employees (as of last public data).
- **No independent security audits** publicly available.

This is a small, lightly-funded French startup. Not a fly-by-night
operation, but not enterprise-grade either. The $1.6M seed with no
follow-on after 3 years is a yellow flag for long-term viability.

---

## LinkedIn: Risk Assessment

### What LinkedIn prohibits (User Agreement Section 8.2)

- Using software that scrapes, crawls, or automates interactions.
- Simulating human behavior on the platform.
- Accessing the platform through unauthorized means.

Unipile violates all three. This is not ambiguous.

### How LinkedIn detects automation

- Activity velocity and timing patterns (ML-based).
- Behavioral anomalies: identical messages to many people, zero
  scroll depth, linear profile viewing patterns, no idle time.
- Content analysis: NLP scanning for duplicate messages, spammy
  keywords, lack of personalization.
- IP reputation and session fingerprinting.
- User reports (people marking your messages as spam).
- Account age, connection count, Social Selling Index score.

### Risk spectrum for different activities

| Activity                          | Risk Level | Why                                   |
|-----------------------------------|------------|---------------------------------------|
| Mass connection requests          | HIGH       | Primary enforcement target. Volume + duplicate messages = easy to detect. |
| Cold outbound messaging           | HIGH       | Same as above. This is what LinkedIn actively fights. |
| Reading inbox / fetching messages | LOW        | Passive. Generates no outbound signal. No content for NLP to flag. No user reports. |
| Responding to existing threads    | LOW-MEDIUM | Replying to people who wrote to you. No user reports (they wanted a reply). Content is unique per conversation (especially with AI drafting). |
| Marking messages as read          | VERY LOW   | Trivial metadata operation. Indistinguishable from normal usage. |
| Archiving / labeling              | N/A        | LinkedIn has no such API surface; we use local DB. Zero platform interaction. |

### The critical distinction

LinkedIn's enforcement is overwhelmingly focused on **outbound spam**
-- unsolicited connection requests and cold messages at scale. Their
ML models are trained on those patterns. Reading your inbox and
replying to people who messaged you first generates almost none of
the signals they look for:

- No duplicate content (each reply is unique, AI-drafted per
  conversation).
- No velocity spike (processing maybe 10-30 conversations, not
  1000).
- No user reports (the other party initiated and wants a response).
- Natural timing (schemail-flow is interactive; you read, think,
  send).

That said, **the risk is not zero.** LinkedIn could detect the session
anomaly (different IP, different user-agent, different TLS fingerprint
than your real browser). The residential proxy mitigates this but
doesn't eliminate it. A "multiple sessions" warning is the most likely
outcome, not a ban.

### Worst case for LinkedIn

Temporary account restriction. LinkedIn rarely does permanent bans for
anything short of egregious spam. Restrictions typically last 24-72
hours and come with a warning.

---

## WhatsApp: Risk Assessment

### What WhatsApp prohibits

- Using unofficial or modified WhatsApp clients.
- Bulk messaging without consent.
- Automated behavior that mimics spam patterns.

Unipile's QR-code pairing technically makes it an "unofficial linked
device," which violates ToS.

### How WhatsApp detects violations

- Behavioral analysis: message velocity, new-chat creation rate,
  block/report ratio from recipients.
- Protocol fingerprinting: WhatsApp can potentially distinguish
  official clients from reverse-engineered protocol implementations,
  though the multi-device protocol is more permissive.
- User reports: the #1 trigger for bans. If people block/report
  you, the account gets flagged.

### Risk spectrum for WhatsApp

| Activity                          | Risk Level | Why                                   |
|-----------------------------------|------------|---------------------------------------|
| Mass outreach to new numbers      | HIGH       | Primary enforcement target. New chat creation is actively monitored. |
| Sending to existing conversations | LOW        | Replying in threads where the other person messaged you. No new-chat signal. |
| Reading messages                  | VERY LOW   | Passive consumption. |
| Marking as read / archiving       | VERY LOW   | Native WhatsApp operations. |
| Labeling                          | VERY LOW   | Native WhatsApp Business feature. |

**Our use case** (reading inbox, replying to people who messaged us)
is about as low-risk as automation gets on WhatsApp. The danger
signals -- mass new-chat creation, high block rates, identical
messages -- simply don't apply.

### Worst case for WhatsApp

Temporary ban (24-72 hours). Permanent bans are typically reserved
for accounts that trigger mass reports or are caught using modified
APKs. The multi-device protocol pairing (QR code) is closer to
"sanctioned" behavior than direct protocol reverse-engineering.

### WhatsApp-specific concern

Fresh accounts are at much higher risk. Unipile's own docs warn:
"Avoid using brand new accounts exclusively for software purposes.
If you use fresh accounts they can be blocked after 2-3 new chats."
This doesn't apply if you're using your established personal number.

---

## Vendor Risk: What If Unipile Dies?

**Data lock-in: Low.** Unipile stores your chat sync state, but all
messages exist on the platforms themselves. If Unipile disappears:

- Your LinkedIn/WhatsApp accounts continue working normally.
- You lose the API access layer (obviously).
- Your local PostgreSQL state store retains all classification data.
- No messages or contacts are lost.

**Session credentials:** If Unipile shuts down abruptly, your LinkedIn
cookies and WhatsApp device pairing may remain active on their servers
until they expire or the infrastructure goes offline. You should:

- Change your LinkedIn password (invalidates stored cookies).
- Unlink the device in WhatsApp settings (Settings > Linked Devices).

**Migration path:** Unipile's API is simple REST. If they die, the
alternatives are:

- Another proxy service (several exist: Phantombuster, etc.)
- Self-hosted Baileys (WhatsApp) + Playwright (LinkedIn) -- more
  work, but the schemail-flow architecture would need minimal changes
  since the `src/unipile.rkt` adapter is the only touchpoint.

---

## Legal Risk

**LinkedIn:**
- The hiQ Labs v. LinkedIn case (2022) established that scraping
  *public* LinkedIn data is not a CFAA violation. However, this
  doesn't cover authenticated access to private messages.
- LinkedIn's User Agreement is a contract. Violating it risks account
  termination but is not criminal.
- GDPR/CCPA: You're accessing your own messages, not scraping others'
  data. The privacy risk is to your own account, not to third parties.

**WhatsApp:**
- WhatsApp's ToS prohibits unofficial clients. Enforcement is account
  restriction, not legal action against individual users.
- Meta has sued companies that built mass-spam tools (e.g., the
  NSO Group / Pegasus case), but that involved surveillance malware,
  not inbox management.

**Bottom line:** No realistic legal risk for personal inbox management.
The risk is purely account-level (temporary restrictions or bans).

---

## Risk Mitigation Strategies

1. **Reply-only posture.** Never use Unipile to initiate contact.
   Only read inbox and respond to existing conversations. This
   eliminates the highest-risk activity categories.

2. **Human-in-the-loop.** schemail-flow is interactive -- you review
   every message and approve every reply. This is not autonomous
   spam. It's an email client with a different backend.

3. **Low volume.** Processing 10-30 conversations per session is
   normal human behavior. Don't batch-process 500 LinkedIn DMs.

4. **Natural timing.** schemail-flow already has natural timing:
   you read, think, maybe edit, then send. Add a 2-3 second delay
   before API sends to avoid sub-second response times.

5. **Use your real, established accounts.** Aged accounts with real
   history and connections are far less likely to be flagged.

6. **Monitor for warnings.** If LinkedIn shows a "suspicious
   activity" or "multiple sessions" warning, pause and reconnect.
   Don't push through.

7. **Keep Unipile credentials rotatable.** Know how to unlink
   (WhatsApp: Linked Devices; LinkedIn: change password) quickly
   if anything feels wrong.

8. **Don't use Unipile for email.** You have proper OAuth-based
   Gmail access already. No need to route email through Unipile.

---

## Daemon-Specific Risk Considerations

The daemon (automated background classification) has a different risk
profile than the interactive flow:

**WhatsApp daemon (classify + label + archive):**
- Low risk. Daemon reads unread chats, classifies, sets labels, and
  archives. All operations are read + metadata updates. No messages
  are sent. This is equivalent to WhatsApp's own notification
  grouping features.
- The only concern is polling frequency. Don't poll every 5 seconds.
  A 5-minute interval mimics "checking your phone periodically."

**LinkedIn daemon (classify + mark read):**
- Lower risk than WhatsApp daemon, because the only platform
  interaction is reading messages and marking them as read.
  Classification state goes entirely to the local database.
- Same polling frequency concern applies.

**Email daemon (existing, unchanged):**
- No new risk. Uses official Gmail API with proper OAuth.

---

## Summary Verdict

For the specific use case of **reading inbox messages and replying to
people who contacted you first**, via Unipile:

| Risk Category    | Level       | Notes                                    |
|------------------|-------------|------------------------------------------|
| WhatsApp account | **Low**     | QR-code pairing is close to sanctioned. Reply-only behavior generates no spam signals. Established personal number has high trust. |
| LinkedIn account | **Low-Med** | Session impersonation violates ToS, but reply-only behavior at low volume is far from enforcement targets. Worst realistic outcome is a temporary restriction and a warning, not a permanent ban. |
| Vendor (Unipile) | **Medium**  | Small company, light funding, no audit. Mitigated by keeping the adapter layer thin (easy to swap) and storing all state in our own database. |
| Legal            | **Negligible** | Personal inbox management is not what lawsuits or regulations target. |

The honest assessment: **this is a calculated gamble, not a sure
thing.** The risk-reward is favorable for personal use at low volume
in reply-only mode, but it's not risk-free. If your LinkedIn account
is mission-critical for your livelihood, that changes the calculus.
