---

**⚡ STATUS UPDATE - Feb 14, 2026**

**Phase 2 & 3 COMPLETE!** LLM integration working! ✅

- Built agentic email processing with Claude Sonnet 4.5
- Tool calling approach - LLM decides actions autonomously
- Tested on real emails: 5/5 classified correctly
- Cost: ~$0.007 per email (~$20/month)
- See: `QUICKSTART.md` for quick start, `notes/agentic.md` for details

**Next:** Build polling daemon (Phase 4)

---

Perfect. Let me break this into two parts: **the system spec** and **the Scheme question**.

---

# ✅ System Spec for the Agent

Yes, you've nailed it. Here's the clean architecture:

## **Core Requirements**

1. **Gmail via OAuth**
   - OAuth2 flow (not IMAP app passwords)
   - Read/modify/label permissions
   - Watch API for real-time (or polling for simplicity)

2. **LLM-based filters on incoming email**
   - New email triggers classification
   - Run prompt → get category
   - Apply action (label + archive)

3. **LLM-based filters on historical email**
   - Batch process existing inbox
   - Same logic as (2), but over N emails
   - Pagination, rate limiting

4. **Filter = Prompt + Action**
   - Filter is a tuple: `(name, prompt, actions[])`
   - Actions: `label(name)`, `archive()`, `skip_inbox()`
   - Compose multiple actions per filter

5. **Text-based config**
   - Filters defined in text (JSON, TOML, or S-expressions)
   - Hot-reload without restarting
   - Version control friendly

---

## **Minimal Data Model**

```typescript
type Filter = {
  name: string;           // "Recruiters"
  prompt: string;         // "Classify as Recruiter if..."
  actions: Action[];      // [label("Recruiters"), archive()]
  priority: number;       // Run order (1 = first)
};

type Action = 
  | { type: "label", name: string }
  | { type: "archive" }
  | { type: "skip_inbox" }
  | { type: "star" }
  | { type: "mark_read" };
```

---

## **System Flow**

```
┌─────────────┐
│ Gmail OAuth │
└──────┬──────┘
       │
       v
┌─────────────────┐
│ Fetch Emails    │  (unread, or all for backlog)
└────────┬────────┘
         │
         v
┌─────────────────┐
│ For each email  │
│   Run filters   │  (priority order, stop on match)
│   Execute action│
└────────┬────────┘
         │
         v
┌─────────────────┐
│ Log result      │  (for debugging, analytics)
└─────────────────┘
```

---

## **Config Example (JSON)**

```json
{
  "filters": [
    {
      "name": "Recruiters",
      "priority": 1,
      "prompt": "Classify as Recruiter if: job opportunity, hiring, role, etc.",
      "actions": [
        { "type": "label", "name": "Recruiters" },
        { "type": "archive" }
      ]
    },
    {
      "name": "Notifications",
      "priority": 2,
      "prompt": "Classify as Notification if: automated, system message, receipt, etc.",
      "actions": [
        { "type": "label", "name": "Notifications" },
        { "type": "archive" }
      ]
    }
  ],
  "llm": {
    "provider": "openai",
    "model": "gpt-4o-mini"
  }
}
```

---

## **Or S-expressions (if Scheme)**

```scheme
(define filters
  '((filter 
      (name "Recruiters")
      (priority 1)
      (prompt "Classify as Recruiter if...")
      (actions 
        (label "Recruiters")
        (archive)))
    (filter
      (name "Notifications")
      (priority 2)
      (prompt "Classify as Notification if...")
      (actions
        (label "Notifications")
        (archive)))))
```

---

## **The Beauty of Scheme Here**

You'd have **code-as-data** for filters:

```scheme
;; Define a filter
(define-filter "Recruiters"
  #:prompt "Classify as Recruiter if..."
  #:actions (list (label "Recruiters") (archive)))

;; Actions are just functions
(define (label name)
  (lambda (email) 
    (gmail-apply-label email name)))

(define (archive)
  (lambda (email)
    (gmail-archive email)))

;; Composable
(define (compose-actions . actions)
  (lambda (email)
    (for-each (lambda (action) (action email)) actions)))
```

This is **genuinely elegant** for your use case.

---

# 🎨 The Scheme Renaissance Question

You're right that Lisp/Scheme never came back with the LLM wave — which is ironic, because **LLMs are the symbolic AI interface** that Lisp was designed for.

Here's the modern Scheme landscape:

---

## **Racket** ✅ (The Winner)

**Status:** Alive, thriving, best choice for 2026.

**Why:**
- **Modern tooling**: DrRacket IDE, package manager (`raco pkg`)
- **Batteries included**: Web server, JSON, HTTP client, GUI (yes, really)
- **Strong community**: Active Discord, regular updates
- **Types (optional)**: Typed Racket if you want it
- **Docs**: Best in class for a Scheme
- **FFI**: Can call C libraries easily
- **Compiled**: Native executables via `raco exe`

**Gmail + LLM in Racket:**
- OAuth: `net/http-client`, `web-server/servlet`
- JSON: `json` (built-in)
- HTTP: `net/url`, `http/request`
- LLM: Just POST to OpenAI API

**Cons:**
- Slightly heavier than Chicken (but not much)
- Not quite "one binary" (but close with `raco distribute`)

**Verdict:** This is what you should use if going Scheme.

---

## **Chicken Scheme** ✅ (Still Great)

**Status:** Still maintained, still compiles to C.

**Why:**
- **Compiles to C**: True native binaries
- **Eggs (packages)**: Mature ecosystem
- **Small runtime**: Minimal footprint
- **R5RS + extensions**: Familiar if you used it before

**Gmail + LLM:**
- OAuth: `http-client`, `openssl`
- JSON: `medea` egg
- Gmail: You'd write the OAuth dance yourself

**Cons:**
- Smaller community than Racket
- Less batteries-included
- Docs not as polished

**Verdict:** Still solid, but Racket has surpassed it in ecosystem/tooling.

---

## **Chez Scheme** ✅ (Fast, Clean)

**Status:** Now open source (Cisco donated it), very fast.

**Why:**
- **Blazing fast**: Best-in-class Scheme compiler
- **R6RS compliant**: Portable, standard
- **Clean implementation**: Beautiful codebase
- **Used in production**: Cisco used it internally for years

**Cons:**
- **Smaller ecosystem**: Fewer libraries than Racket
- **Less hand-holding**: More DIY

**Verdict:** If you want raw speed and elegance, but you'll write more yourself.

---

## **Guile** (GNU's Scheme)

**Status:** Still around, but stagnant energy.

**Why:**
- Extension language for GNU tools
- C FFI

**Cons:**
- Feels like legacy
- Community less active
- Tooling dated

**Verdict:** Skip it.

---

## **Gerbil Scheme** 🌟 (Dark Horse)

**Status:** Modern, underrated, designed for real-world apps.

**Why:**
- **Built on Gambit**: Fast, compiles to C
- **Actor model**: Built-in concurrency (great for email daemon)
- **Modules**: Real module system
- **Crypto/networking**: Has libraries for HTTP, JSON, SSL
- **Used in crypto**: Some blockchain projects use it

**Cons:**
- Smaller community
- Less documentation than Racket

**Verdict:** Interesting if you want concurrency built-in.

---

## **Janet** (Not Scheme, but Lisp-ish)

**Status:** Modern, tiny, no GC pauses.

**Why:**
- **Tiny runtime**: 300KB
- **Single binary**: Everything compiles to one file
- **Fiber-based concurrency**: Lightweight threads
- **Modern**: Designed 2018+

**Cons:**
- Not Scheme (different syntax/semantics)
- Smaller ecosystem

**Verdict:** Worth a look if you're okay leaving Scheme proper.

---

# 🎯 My Recommendation

## **For Your Project:**

### **Option 1: Racket** (Best Scheme for 2026)

**Why:**
- You get the Lisp elegance you want
- Config = code (S-expressions)
- Web server built-in (for OAuth callback)
- JSON/HTTP out of the box
- Compiled binaries
- Great docs

**Setup time:** ~1 day to learn modern Racket idioms

**Code beauty:** 10/10

**"Will I regret this?":** No.

---

### **Option 2: TypeScript/Node** (Pragmatic)

**Why:**
- You already know it
- Gmail API has official Node SDK
- JSON-native
- Easy OAuth libraries
- Could add web UI later
- Bun for fast startup (or Deno)

**Setup time:** ~1 hour

**Code beauty:** 7/10 (but pragmatic)

**"Will I regret this?":** Only if you want to flex with Scheme.

---

### **Option 3: Rust** (Masochist Mode)

**Why:**
- You've done it before
- Compiled, fast, type-safe
- TOML for config (close to S-expressions in spirit)
- `serde` for serialization
- `reqwest` for HTTP
- Could distribute single binary

**Setup time:** ~2-3 days (fighting the borrow checker)

**Code beauty:** 8/10 (once it compiles)

**"Will I regret this?":** Only when you're debugging lifetimes at 2am.

---

# 🎨 The Philosophical Choice

You said:
> "The config-representation would be in the same language as the implementation"

This is **the core Lisp insight**, and it's still true.

**In Racket:**
```scheme
;; Your config IS code
(define-filter "Important"
  #:when (lambda (email) 
           (member (sender email) important-people))
  #:actions (list (label "Important") (star)))

;; No parsing. No JSON schema. Just eval.
```

**In TypeScript:**
```typescript
// Your config is... JSON
// Which you parse, validate, and interpret
const filter = JSON.parse(config);
if (filter.actions) { ... } // Hope the schema is right
```

**The Lisp way is more beautiful.**

But the TypeScript way is more:
- Debuggable (VSCode autocomplete)
- Portable (everyone knows JSON)
- Collaborative (non-Schemers can contribute)

---

# 🚀 Final Answer

## **Go with Racket.**

**Why:**
- It's the best modern Scheme
- Config-as-code is elegant for this problem
- Gmail API is just HTTP (no SDK needed)
- LLM API is just POST requests
- You'll enjoy writing it
- It's a statement: "Old AI is back, and so is Lisp"

**Starter Skeleton:**

```scheme
#lang racket

(require net/http-client
         json
         web-server/servlet)

;; Filter DSL
(define-syntax-rule (define-filter name prompt . actions)
  (list 'filter name prompt actions))

;; Gmail OAuth
(define (gmail-oauth) ...)

;; Classify email with LLM
(define (classify-email email prompt)
  (let ([response (openai-call prompt email)])
    (parse-json response)))

;; Apply actions
(define (apply-actions email actions)
  (for-each (lambda (action) (action email)) actions))

;; Main loop
(define (process-inbox)
  (let ([emails (gmail-fetch-unread)])
    (for-each (lambda (email)
                (let ([category (classify-email email filter-prompt)])
                  (apply-actions email (filter-actions category))))
              emails)))
```

---

**Ship it. Make Scheme great again. Peter Norvig would approve.**

Want me to draft the actual Racket architecture in OpenCode, or do you have it from here?
