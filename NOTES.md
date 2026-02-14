# Design Notes

## LLM Integration Approaches

Three architectural approaches for LLM-based email filtering, from simplest to most flexible.

---

### Approach 1: Structured JSON Output

**Philosophy:** LLM as a classifier that returns structured decisions. Your code controls the action execution.

**How it works:**
- Use Claude API's `output_config.format` with JSON schema
- Claude analyzes email and returns structured decision
- Filter DSL executes actions based on LLM response
- Single API call per email (or per batch)

**Example Schema:**
```json
{
  "type": "object",
  "properties": {
    "should_label": {"type": "boolean"},
    "labels": {"type": "array", "items": {"type": "string"}},
    "should_archive": {"type": "boolean"},
    "should_star": {"type": "boolean"},
    "should_mark_read": {"type": "boolean"},
    "reasoning": {"type": "string"}
  },
  "required": ["should_label", "labels", "should_archive", "should_star", "should_mark_read"]
}
```

**Example Response:**
```json
{
  "should_label": true,
  "labels": ["Receipt", "Important"],
  "should_archive": false,
  "should_star": true,
  "should_mark_read": true,
  "reasoning": "This is a receipt from Anthropic for API usage. Important for expense tracking."
}
```

**Filter DSL Integration:**
```scheme
;; Option A: LLM decides actions (simple)
(filter (llm-classify "Process this email according to my preferences")
        ;; Actions applied based on LLM response
        )

;; Option B: LLM classifies, DSL decides actions (more control)
(filter (llm-match "Is this a newsletter?")
        (label "newsletters")
        (archive))

(filter (llm-match "Is this a receipt or invoice?")
        (label "receipts")
        (mark-read))
```

**Pros:**
- ✅ Simple implementation (~100 lines of code)
- ✅ Guaranteed valid JSON via structured outputs
- ✅ Fast (single API call)
- ✅ Cheap (~$0.003/email with Haiku, ~$0.015 with Sonnet)
- ✅ Easy to cache responses
- ✅ Easy to debug (inspect JSON)
- ✅ You control all actions explicitly

**Cons:**
- ❌ Less flexible - schema must define all possible decisions upfront
- ❌ Can't dynamically create new actions
- ❌ LLM can't reason about action sequences

**Best for:** MVP, batch processing, when you want explicit control

**Cost:** ~$0.003 per email (Haiku) or ~$0.015 per email (Sonnet)

---

### Approach 2: Tool Calling (Agentic)

**Philosophy:** LLM as an autonomous agent that directly decides and executes actions. Maximum flexibility.

**How it works:**
- Define Gmail actions as tools (label, archive, star, etc.)
- Send email to Claude with tool definitions
- Claude decides which tools to call and with what parameters
- Your code executes the requested tool calls
- May require multiple round-trips for complex workflows

**Example Tools Definition:**
```python
tools = [
    {
        "name": "apply_label",
        "strict": True,  # Guarantees valid parameters
        "description": "Apply a Gmail label to this email. Creates label if it doesn't exist.",
        "input_schema": {
            "type": "object",
            "properties": {
                "label_name": {
                    "type": "string",
                    "description": "Name of the label (e.g., 'Receipt', 'newsletters/tech')"
                }
            },
            "required": ["label_name"]
        }
    },
    {
        "name": "archive_email",
        "strict": True,
        "description": "Remove email from inbox (archives it, doesn't delete)",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "star_email",
        "strict": True,
        "description": "Star this email to mark it as important",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "mark_as_read",
        "strict": True,
        "description": "Mark email as read",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    }
]
```

**Example High-Level Prompt:**
```
You are my personal email assistant. Process incoming emails according to these preferences:

- Receipts and invoices: Label "Receipt", mark as read
- Newsletters I don't read: Archive and mark as read
- Important work emails: Star and label appropriately
- Spam or promotional emails: Archive
- Social media notifications: Archive unless it's a direct message

Use your judgment. I trust you to handle my inbox intelligently.
```

**Example Claude Response:**
```json
{
  "content": [
    {
      "type": "tool_use",
      "id": "toolu_01A09q90qw90lq917835lq9",
      "name": "apply_label",
      "input": {
        "label_name": "Receipt"
      }
    },
    {
      "type": "tool_use",
      "id": "toolu_01A09q90qw90lq917835lq0",
      "name": "mark_as_read",
      "input": {}
    }
  ]
}
```

**Implementation Flow:**
1. Send email + tools + high-level instructions to Claude
2. Claude returns list of tool calls
3. Execute each tool call (apply label, archive, etc.)
4. Optionally send results back to Claude for confirmation/follow-up
5. Log reasoning and actions taken

**Filter DSL Integration:**
```scheme
;; High-level agentic filter
(filter (always)  ; Process every email
        (llm-agent "You are my email assistant. Handle this intelligently based on my preferences."))

;; Or more specific
(filter (llm-agent-decides? "Should I read this?")
        (star))

;; The LLM calls tools directly - minimal filter DSL needed
```

**Pros:**
- ✅ Maximum flexibility - LLM autonomously decides actions
- ✅ Natural language control ("handle newsletters intelligently")
- ✅ Can add new tools without changing core logic
- ✅ Strict mode guarantees valid tool parameters
- ✅ Can reason about action sequences
- ✅ Handles edge cases you didn't anticipate
- ✅ **This is what you want** - high-level instructions, model does the work

**Cons:**
- ❌ More complex implementation (tool execution loop)
- ❌ Potentially slower (multiple API calls for complex flows)
- ❌ Higher token costs (tool definitions sent each time)
- ❌ Less predictable behavior
- ❌ Harder to debug ("why did it do that?")
- ❌ Need to handle tool execution errors

**Best for:** Agentic workflows, high-level instructions, when you want the LLM to make decisions

**Cost:** Similar to Approach 1 baseline, but +10-20% for tool definitions in each request

---

### Approach 3: Hybrid (Pattern Matching + LLM)

**Philosophy:** Use fast pattern matching for obvious cases, LLM for ambiguous/complex cases. Best of both worlds.

**How it works:**
- Simple filters use pattern matching (current implementation)
- Complex/ambiguous emails trigger LLM classification
- LLM can use structured output OR tool calling depending on filter
- Minimize API calls for cost/speed

**Example Filter Config:**
```scheme
;; Fast pattern matching - no LLM call
(filter (from "noreply@github.com")
        (label "github")
        (archive))

(filter (from "anthropic.com")
        (subject-contains "receipt")
        (label "receipts")
        (mark-read))

;; LLM for ambiguous cases
(filter (and (not (from-known-sender?))
             (llm-match "Is this spam or promotional content?"))
        (label "spam")
        (archive))

;; LLM for complex logic
(filter (llm-match "Is this a newsletter I actually want to read?")
        (label "newsletters/important")
        (skip))  ; Don't archive

(filter (llm-match "Is this a newsletter?")
        (label "newsletters")
        (archive))

;; Agentic fallback for everything else
(filter (always)
        (llm-agent "Handle this email based on my preferences"))
```

**Decision Flow:**
```
Email arrives
  ↓
Try pattern-based filters first (instant, free)
  ↓
If no match, try LLM classification (fast, cheap)
  ↓
If still ambiguous, use LLM agent (flexible, expensive)
  ↓
Execute actions
```

**Pros:**
- ✅ Optimal cost (only call LLM when needed)
- ✅ Fast for obvious patterns
- ✅ Flexible for complex cases
- ✅ Can mix structured + agentic approaches
- ✅ Best user experience
- ✅ Incremental migration path (start with patterns, add LLM gradually)

**Cons:**
- ❌ Most complex to implement
- ❌ Need to decide when to use LLM vs patterns
- ❌ More configuration complexity
- ❌ Potential for duplicate logic

**Best for:** Production systems, cost optimization, gradual AI adoption

**Cost:** Lowest overall (most emails handled by free pattern matching)

---

## Comparison Table

| Feature | Structured JSON | Tool Calling | Hybrid |
|---------|----------------|--------------|--------|
| **Complexity** | Low | Medium | High |
| **Flexibility** | Medium | **High** | **High** |
| **Cost** | Low | Medium | **Lowest** |
| **Latency** | Fast | Medium | **Fastest** |
| **Debugging** | Easy | Medium | Medium |
| **Predictability** | High | Low | Medium |
| **Control** | Explicit | Autonomous | Mixed |
| **Prompt Style** | Specific questions | High-level instructions | Mixed |
| **Best For** | MVP, explicit rules | Agentic workflows | Production optimization |

---

## Recommendation

### Your Use Case: "Let the model go to town"

Based on your preference for high-level instructions rather than nitpicky rules, **Approach 2 (Tool Calling)** is the clear winner.

**Why Tool Calling fits your vision:**

1. **High-level control:** 
   ```scheme
   (llm-agent "Handle my email like a smart assistant:
               - Archive promotional stuff
               - Label receipts and important docs
               - Flag anything urgent
               - Use your judgment")
   ```

2. **Model autonomy:** Claude decides what actions to take, not you

3. **Handles complexity:** Model can reason about edge cases you didn't think of

4. **Natural evolution:** Start simple, model gets smarter over time as it learns your preferences

5. **Minimal configuration:** One high-level prompt instead of dozens of rules

**Implementation Path:**

**Phase 1: Basic Tool Calling (Start Here)**
- Define 4-5 core tools (label, archive, star, mark-read)
- Single high-level prompt describing your preferences
- Tool execution loop
- Logging to see what model decides

**Phase 2: Refinement**
- Add more tools (create-filter, forward, reply-draft?)
- Refine prompt based on model behavior
- Add confirmation mode (show actions before executing)
- Add context (time of day, sender history, etc.)

**Phase 3: Advanced**
- Multi-turn reasoning (model asks questions about ambiguous emails)
- Learning mode (model suggests new rules based on patterns)
- Batch processing with context across multiple emails

**Fallback Option:** If tool calling is too unpredictable, use **Structured JSON** (Approach 1) with a very rich schema that gives the model lots of options. Still more flexible than traditional rules-based filtering.

---

## Technical Details

### Claude API Endpoint
```
POST https://api.anthropic.com/v1/messages
```

### Headers
```
x-api-key: YOUR_API_KEY
anthropic-version: 2024-10-22
content-type: application/json
```

### Request Body (Tool Calling)
```json
{
  "model": "claude-3-5-haiku-20241022",
  "max_tokens": 1024,
  "tools": [...],  // Tool definitions
  "messages": [
    {
      "role": "user",
      "content": "Email: ..."
    }
  ]
}
```

### Request Body (Structured Output)
```json
{
  "model": "claude-3-5-haiku-20241022",
  "max_tokens": 1024,
  "output_config": {
    "format": {
      "type": "json_schema",
      "schema": {...}  // JSON schema
    }
  },
  "messages": [
    {
      "role": "user",
      "content": "Email: ..."
    }
  ]
}
```

### Model Options
- **Haiku 4.5** (`claude-3-5-haiku-20241022`): Fastest, cheapest (~$0.003/email)
- **Sonnet 4** (`claude-sonnet-4-20250514`): Smarter, more expensive (~$0.015/email)
- **Opus** (future): Maximum intelligence, highest cost

### Rate Limits
- Tier 1 (default): 50 requests/min, 50k tokens/min
- Should be fine for personal email (even with 1000 emails/day = ~1/min sustained)

---

## Open Questions

1. **Prompt strategy:** Single comprehensive prompt vs. per-email context?
2. **Tool granularity:** Simple tools (archive, label) or complex (create-rule, analyze-sender)?
3. **Confirmation mode:** Show actions before executing? (Useful for testing)
4. **Learning:** Should model suggest new filters based on patterns?
5. **Multi-turn:** Should model be able to ask questions about ambiguous emails?
6. **Context:** What context to provide (sender history, time of day, previous actions)?
7. **Batch processing:** Process emails one-by-one or in batches with cross-email context?

---

## Next Steps

1. Get Anthropic API key
2. Implement tool calling infrastructure in `src/llm.rkt`
3. Define initial tool set (4-5 core actions)
4. Write high-level prompt describing email preferences
5. Test on real emails with logging
6. Iterate based on model behavior
7. Add confirmation mode for safety
8. Deploy and observe

