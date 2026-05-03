# Plan: Abstract LLM Calls + Add Vertex AI Backend

## Motivation

Run schemail on a work machine where direct Anthropic API access may not be
available, but Claude is accessible via Google Cloud Vertex AI.

## Current State

All 5 LLM call sites hit `https://api.anthropic.com/v1/messages` with the same
auth pattern (`x-api-key` + `anthropic-version: 2023-06-01`) using `net/http-easy`.

| File | API Style | Model | Retry? | Status check? | Token logging? |
|------|-----------|-------|--------|---------------|----------------|
| `src/llm-classifier.rkt:117` | Structured output (`output_config` / `json_schema`) | haiku-4-5 (parameterized) | Yes (3x, exp backoff) | Yes | Yes |
| `src/label-consolidation.rkt:95` | Structured output (`output_config` / `json_schema`) | haiku-4-5 | No | Yes | Yes |
| `src/label-utils.rkt:103` | Plain messages | haiku-4-5 | No (fallback to normalize) | Yes | No |
| `src/reply-drafter.rkt:61` | Plain messages | haiku-4-5 (parameterized) | No | **No** | No |
| `src/llm.rkt:92` | Tool calling | sonnet-4-5 (parameterized) | No | Yes | Yes |

## Steps

### Step 1: Create `src/llm-client.rkt` — unified LLM client

A single module providing one function (e.g., `call-claude`) handling:

- Endpoint URL, auth headers, API version
- POST with JSON body
- Status code check, retry logic (generalize from `llm-classifier.rkt`)
- Token usage logging
- Response parsing (return parsed JSON body)

Configurable via Racket parameters:

- `current-backend` — `'anthropic` (default) or `'vertex-ai`
- `current-model` — stays as-is (re-exported from here)

Signature:

```racket
(call-claude #:model model
             #:messages messages
             #:max-tokens max-tokens
             #:tools tools           ; optional
             #:output-config config  ; optional
             #:system system)        ; optional
```

### Step 2: Implement Vertex AI backend in `llm-client.rkt`

Key differences from direct Anthropic API:

- **Endpoint:** `https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/{REGION}/publishers/anthropic/models/{MODEL}:rawPredict`
- **Auth:** Bearer token from Google ADC (Application Default Credentials) instead of `x-api-key` header
- **Body:** Nearly identical — same `messages`, `max_tokens`, `tools`, etc. The `anthropic_version` field goes in the request body instead of a header.
- **Model field:** Not needed in body (it's in the URL), or may be ignored.

Config via env vars:

- `VERTEX_PROJECT` — GCP project ID
- `VERTEX_REGION` — e.g., `us-east5`
- `GOOGLE_APPLICATION_CREDENTIALS` or Application Default Credentials

For ADC token retrieval: shell out to `gcloud auth print-access-token` or
implement OAuth2 service account token exchange. The `gcloud` approach is
simpler for local dev; service account JWT is better for production.

### Step 3: Update the 5 call sites

Replace inline HTTP calls with `(call-claude ...)` from `llm-client.rkt`.
Each file drops ~15-20 lines of boilerplate.

### Step 4: Fix hardcoded paths in `src/email-sender.rkt`

Lines 18-19 hardcode `/home/danenberg/bin/pandoc` and
`/home/danenberg/.cargo/bin/css-inline`. Replace with
`(find-executable-path "pandoc")` etc.

### Step 5: CLI flag / env var for backend selection

Add `--backend vertex-ai` flag to the CLI, or read from `LLM_BACKEND` env var.
Wire it to `(current-backend)` parameter.

## Risk: Structured Output on Vertex AI

The `output_config` with `json_schema` (used by `llm-classifier.rkt` and
`label-consolidation.rkt`) may not be supported on Vertex AI's Claude endpoint.

Fallback options if unsupported:

1. Use tool calling to simulate structured output (Vertex does support tools)
2. Use prompt-based JSON extraction with validation/retry

**Action:** Verify Vertex AI Claude structured output support before implementing.

## Estimated Scope

| Step | Files modified | New files | Effort |
|------|---------------|-----------|--------|
| 1. `llm-client.rkt` | — | 1 | Medium |
| 2. Vertex AI backend | — | (same file) | Medium |
| 3. Update call sites | 5 | — | Low |
| 4. Fix hardcoded paths | 1 | — | Trivial |
| 5. CLI flag | 1-2 | — | Low |

## Bonus: Improve `reply-drafter.rkt`

While refactoring, add the missing status code check, error handling, and token
logging that the other call sites already have. This comes free with the
unified client.
