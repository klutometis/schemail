#lang racket

;; Label consolidation: LLM-powered dedup and merge of Gmail labels
;; Used by `schemail consolidate` to clean up duplicate/variant labels

(require "gmail.rkt"
         "label-utils.rkt"
         json
         net/url
         net/http-easy)

(provide consolidate-labels!
         propose-merges)

;; ============================================================================
;; Configuration
;; ============================================================================

(define CLAUDE-API-URL "https://api.anthropic.com/v1/messages")
(define CONSOLIDATION-MODEL "claude-haiku-4-5")
(define ANTHROPIC-API-KEY (getenv "ANTHROPIC_API_KEY"))

(unless ANTHROPIC-API-KEY
  (error "ANTHROPIC_API_KEY environment variable not set"))

;; ============================================================================
;; Merge Proposal (LLM)
;; ============================================================================

(define MERGE-PROMPT
  "You are analyzing Gmail labels to find duplicates and variants that should be merged.

Given this list of labels with message counts, identify groups that should be merged.
Consider:
- Plural/singular variants (Membership vs Memberships)
- Verb form variants (Respond vs Responding)  
- Typos and misspellings (Ppta, Pyta -> PTA)
- Acronyms that were incorrectly title-cased (Pta -> PTA, Hoa -> HOA, Ayso -> AYSO)
- Semantically equivalent labels (Sports vs Sporting Events, News vs Newsletters)

For each merge group, choose the best canonical name:
- Use the proper casing (acronyms uppercase: PTA, HOA, AYSO)
- Prefer the label with more messages when names are similar
- Use singular form unless plural is more natural

Also identify any standalone labels that just need casing fixes (e.g., Hoa -> HOA).

Return a JSON array of merge groups. Each group has:
- \"canonical\": the target label name (properly cased)
- \"sources\": array of current label names to merge INTO the canonical (include the canonical's current name if it needs renaming)
- \"reason\": brief explanation

Only include labels that need changes. Labels that are fine as-is should be omitted.

Example output:
[
  {\"canonical\": \"PTA\", \"sources\": [\"Pta\", \"Ppta\", \"Pyta\"], \"reason\": \"Typos and incorrect casing of PTA acronym\"},
  {\"canonical\": \"Membership\", \"sources\": [\"Membership\", \"Memberships\"], \"reason\": \"Singular/plural variant\"}
]

LABELS:
{labels}")

;; JSON schema for merge proposals
(define MERGE-SCHEMA
  (hasheq 'type "object"
          'properties (hasheq 'merges (hasheq 'type "array"
                                              'items (hasheq 'type "object"
                                                             'properties (hasheq 'canonical (hasheq 'type "string")
                                                                                'sources (hasheq 'type "array"
                                                                                                 'items (hasheq 'type "string"))
                                                                                'reason (hasheq 'type "string"))
                                                             'required '("canonical" "sources" "reason")
                                                             'additionalProperties #f)))
          'required '("merges")
          'additionalProperties #f))

;; Ask the LLM to propose merge groups
(define (propose-merges labels-hash)
  (displayln "\nAsking LLM to identify label duplicates and variants...")
  
  ;; Format labels for prompt
  (define labels-text (format-labels-for-prompt labels-hash))
  (define final-prompt (string-replace MERGE-PROMPT "{labels}" labels-text))
  
  (define request-body
    (hasheq 'model CONSOLIDATION-MODEL
            'max_tokens 4096
            'output_config (hasheq 'format (hasheq 'type "json_schema"
                                                    'schema MERGE-SCHEMA))
            'messages (list (hasheq 'role "user"
                                    'content final-prompt))))
  
  (define response
    (post CLAUDE-API-URL
          #:headers (hash 'x-api-key ANTHROPIC-API-KEY
                         'anthropic-version "2023-06-01"
                         'content-type "application/json")
          #:data (jsexpr->string request-body)))
  
  (unless (= (response-status-code response) 200)
    (error 'propose-merges
           "API request failed: ~a\n~a"
           (response-status-code response)
           (bytes->string/utf-8 (response-body response))))
  
  (define response-json (string->jsexpr (bytes->string/utf-8 (response-body response))))
  
  ;; Log token usage
  (define usage (hash-ref response-json 'usage #f))
  (when usage
    (displayln (format "Tokens - Input: ~a, Output: ~a"
                      (hash-ref usage 'input_tokens 0)
                      (hash-ref usage 'output_tokens 0))))
  
  ;; Extract merges from response
  (define content (hash-ref response-json 'content '()))
  (when (empty? content)
    (error 'propose-merges "No content in API response"))
  
  (define first-content (car content))
  (define result-json
    (with-handlers ([exn:fail? (lambda (e)
                                 (error 'propose-merges "Failed to parse merge proposals: ~a" (exn-message e)))])
      (string->jsexpr (hash-ref first-content 'text))))
  
  (hash-ref result-json 'merges '()))

;; ============================================================================
;; Merge Execution
;; ============================================================================

;; Execute a single merge: move messages from source labels to canonical, delete sources.
;; Handles Gmail's case-insensitive label names by renaming when needed.
(define (execute-merge canonical sources)
  ;; Step 1: Find or establish the target label.
  ;; Gmail labels are case-insensitive, so we can't create "PTA" when "Pta" exists.
  ;; Instead, find a case-insensitive match among sources and rename it.
  (define canonical-id (gmail-find-label-by-name canonical))
  
  (define target-id
    (cond
      ;; Canonical already exists with exact name — use it
      [canonical-id canonical-id]
      [else
       ;; Look for a case-insensitive match among sources to rename
       (define rename-source
         (for/first ([s sources]
                     #:when (and (string-ci=? s canonical)
                                 (not (string=? s canonical))))
           s))
       (cond
         [rename-source
          ;; Rename the case-insensitive match to the canonical casing
          (define source-id (gmail-find-label-by-name rename-source))
          (displayln (format "  Renaming ~a -> ~a" rename-source canonical))
          (gmail-update-label source-id #:name canonical)
          source-id]
         [else
          ;; Truly new label — create it
          (displayln (format "  Creating label: ~a" canonical))
          (hash-ref (gmail-create-label canonical) 'id)])]))
  
  ;; Step 2: Move messages from remaining sources into target, then delete sources
  (for ([source sources])
    ;; Skip if this source IS the target (exact match or was just renamed)
    (when (not (string-ci=? source canonical))
      (define source-id (gmail-find-label-by-name source))
      (when source-id
        (displayln (format "  Moving messages from ~a to ~a..." source canonical))
        (let loop ([page-token #f]
                   [moved 0])
          (define response (gmail-list-messages #:query (format "label:~a" source)
                                               #:max-results 500
                                               #:page-token page-token))
          (define messages (hash-ref response 'messages '()))
          (unless (empty? messages)
            (define ids (map (lambda (m) (hash-ref m 'id)) messages))
            (gmail-batch-modify ids
                                #:add-labels (list target-id)
                                #:remove-labels (list source-id))
            (define new-moved (+ moved (length ids)))
            (define next-token (hash-ref response 'nextPageToken #f))
            (if next-token
                (loop next-token new-moved)
                (displayln (format "    Moved ~a messages" new-moved)))))
        
        (displayln (format "  Deleting label: ~a" source))
        (gmail-delete-label source-id)))))

;; ============================================================================
;; Public API
;; ============================================================================

;; Run the full consolidation flow: propose merges, confirm, execute
(define (consolidate-labels! labels-hash #:yes? [auto-confirm? #f])
  ;; Get merge proposals from LLM
  (define merges (propose-merges labels-hash))
  
  (when (empty? merges)
    (displayln "\nNo merges needed! All labels look clean.")
    (void))
  
  (unless (empty? merges)
    ;; Display proposed merges
    (displayln "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    (displayln "Proposed Label Merges")
    (displayln "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    
    (for ([merge merges]
          [i (in-naturals 1)])
      (define canonical (hash-ref merge 'canonical))
      (define sources (hash-ref merge 'sources))
      (define reason (hash-ref merge 'reason))
      
      ;; Calculate total message count
      (define total-count
        (for/sum ([s sources])
          (hash-ref labels-hash s 0)))
      ;; Also count canonical if not in sources
      (define canonical-count (hash-ref labels-hash canonical 0))
      (define grand-total (+ total-count
                             (if (member canonical sources) 0 canonical-count)))
      
      (displayln (format "~a. ~a (~a messages)" i canonical grand-total))
      (displayln (format "   Merging: ~a" (string-join sources ", ")))
      (displayln (format "   Reason: ~a" reason))
      (displayln ""))
    
    ;; Confirm
    (define proceed?
      (if auto-confirm?
          #t
          (let ()
            (display "Proceed with merges? (yes/no) ")
            (flush-output)
            (define answer (read-line))
            (equal? answer "yes"))))
    
    (if proceed?
        (begin
          (displayln "\nExecuting merges...\n")
          (for ([merge merges])
            (define canonical (hash-ref merge 'canonical))
            (define sources (hash-ref merge 'sources))
            
            (execute-merge canonical sources)
            
            (displayln (format "  ✓ ~a" canonical)))
          
          (displayln "\n✓ Consolidation complete!"))
        (displayln "\nCancelled. No changes made."))))
