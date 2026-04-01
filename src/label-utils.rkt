#lang racket

;; Shared utilities for Gmail label operations
;; Used by both llm.rkt and llm-classifier.rkt

(require "gmail.rkt"
         json
         net/url
         net/http-easy)

(provide normalize-label
         resolve-canonical-label
         ensure-schemail-marker
         ensure-label-hierarchy
         apply-content-and-marker-labels
         archive-message
         get-labels-with-counts
         format-labels-for-prompt
         update-label-hash!)

;; ============================================================================
;; Label Normalization
;; ============================================================================

;; Normalize a single label part: titlecase + replace non-alphanumeric with spaces
(define (normalize-label-part part)
  (string-titlecase 
   (string-trim (regexp-replace* #rx"[^a-zA-Z0-9]+" part " "))))

;; Normalize a label name (handles hierarchical labels with /)
;; Examples:
;;   "verification-code" -> "Verification Code"
;;   "Newsletter/Marketing" -> "Newsletter/Marketing"
;;   "news_letter/order-confirmation" -> "News Letter/Order Confirmation"
(define (normalize-label raw-label)
  (if (string-contains? raw-label "/")
      (string-join (map normalize-label-part (string-split raw-label "/")) "/")
      (normalize-label-part raw-label)))

;; ============================================================================
;; LLM-Powered Label Resolution
;; ============================================================================

(define CLAUDE-API-URL "https://api.anthropic.com/v1/messages")
(define RESOLUTION-MODEL "claude-haiku-4-5")
(define ANTHROPIC-API-KEY (getenv "ANTHROPIC_API_KEY"))

;; In-memory cache: raw label -> resolved canonical label (within a single run)
(define canonical-cache (make-hash))

(define RESOLVE-PROMPT
  "Given this proposed email label and existing labels, return the best label to use.

Rules:
1. If the proposed label is a duplicate/variant of an existing label (plural, abbreviation, typo, gerund, synonym), return the existing label name exactly.
2. If it's a genuinely new label, return it with proper formatting:
   - Acronyms should be uppercase (PTA, HOA, AYSO, DMV, FAQ, HTML, CSS, NFL, NBA, MLB)
   - Regular words in Title Case
   - Keep it concise

Proposed label: \"{proposed}\"

Existing labels:
{existing_labels}

Return ONLY the label name. Nothing else.")

;; Ask the LLM to resolve a proposed label against existing labels.
;; Returns the canonical label name (either an existing label or a properly-cased new one).
;; Results are cached in-memory for the duration of a run.
(define (resolve-canonical-label raw-label labels-hash)
  ;; Check cache first
  (define cached (hash-ref canonical-cache raw-label #f))
  (when cached
    (displayln (format "  → Label cache hit: ~a -> ~a" raw-label cached))
    cached)
  
  (or cached
      ;; If no existing labels, just normalize
      (if (hash-empty? labels-hash)
          (let ([normalized (normalize-label raw-label)])
            (hash-set! canonical-cache raw-label normalized)
            normalized)
          ;; Call LLM for resolution
          (with-handlers ([exn:fail?
                           (lambda (e)
                             (displayln (format "  ⚠ Label resolution failed (~a), falling back to normalize" (exn-message e)))
                             (define fallback (normalize-label raw-label))
                             (hash-set! canonical-cache raw-label fallback)
                             fallback)])
            (define existing-text (format-labels-for-prompt labels-hash))
            (define prompt (string-replace 
                           (string-replace RESOLVE-PROMPT "{proposed}" raw-label)
                           "{existing_labels}" existing-text))
            
            (define request-body
              (hasheq 'model RESOLUTION-MODEL
                      'max_tokens 64
                      'messages (list (hasheq 'role "user"
                                              'content prompt))))
            
            (define response
              (post CLAUDE-API-URL
                    #:headers (hash 'x-api-key ANTHROPIC-API-KEY
                                   'anthropic-version "2023-06-01"
                                   'content-type "application/json")
                    #:data (jsexpr->string request-body)))
            
            (unless (= (response-status-code response) 200)
              (error 'resolve-canonical-label "API request failed: ~a" 
                     (response-status-code response)))
            
            (define response-json (string->jsexpr (bytes->string/utf-8 (response-body response))))
            (define content (hash-ref response-json 'content '()))
            (when (empty? content)
              (error 'resolve-canonical-label "No content in response"))
            
            (define resolved (string-trim (hash-ref (car content) 'text "")))
            
            ;; Sanity check: if resolved is empty, fall back
            (when (equal? resolved "")
              (error 'resolve-canonical-label "Empty response"))
            
            (displayln (format "  → Label resolved: ~a -> ~a" raw-label resolved))
            (hash-set! canonical-cache raw-label resolved)
            resolved))))

;; ============================================================================
;; Schemail Marker Management
;; ============================================================================

;; Ensure the "Schemail" marker label exists and is properly hidden.
;; Returns the label ID.
;; The marker is hidden from both sidebar (labelListVisibility: labelHide)
;; and message list (messageListVisibility: hide).
(define (ensure-schemail-marker)
  (define marker-id (gmail-find-label-by-name "Schemail"))
  (if marker-id
      marker-id
      (let* ([marker-label (begin
                             (displayln "  → Creating Schemail marker label")
                             (gmail-create-label "Schemail"))]
             [new-id (hash-ref marker-label 'id)])
        (displayln "  → Hiding Schemail from sidebar and message list")
        (gmail-update-label new-id 
                           #:label-list-visibility "labelHide"
                           #:message-list-visibility "hide")
        new-id)))

;; ============================================================================
;; Hierarchical Label Handling
;; ============================================================================

;; Ensure parent labels exist for hierarchical labels (e.g., "Newsletter/Marketing")
;; Gmail requires parent labels to exist before creating child labels.
(define (ensure-label-hierarchy label-name)
  (when (string-contains? label-name "/")
    (define parent-name (car (string-split label-name "/")))
    (define parent-id (gmail-find-label-by-name parent-name))
    (unless parent-id
      (displayln (format "  → Creating parent label: ~a" parent-name))
      (gmail-create-label parent-name))))

;; ============================================================================
;; Label Application
;; ============================================================================

;; Apply both content label and Schemail marker to a message.
;; Creates labels if they don't exist.
;; Returns the content label ID (for reference).
(define (apply-content-and-marker-labels message-id content-label marker-id)
  ;; Ensure hierarchy exists
  (ensure-label-hierarchy content-label)
  
  ;; Find or create content label
  (define content-label-id 
    (or (gmail-find-label-by-name content-label)
        (let ([new-label (begin
                           (displayln (format "  → Creating label: ~a" content-label))
                           (gmail-create-label content-label))])
          (hash-ref new-label 'id))))
  
  ;; Apply both labels
  (displayln (format "  → Applying labels: ~a + Schemail (marker)" content-label))
  (gmail-modify-message message-id #:add-labels (list content-label-id marker-id))
  (displayln "  ✓ Labels applied")
  
  content-label-id)

;; ============================================================================
;; Archive Operation
;; ============================================================================

;; Archive a message (remove from INBOX)
(define (archive-message message-id)
  (displayln "  → Archiving (removing from INBOX)")
  (gmail-modify-message message-id #:remove-labels '("INBOX"))
  (displayln "  ✓ Archived"))

;; ============================================================================
;; Label Discovery
;; ============================================================================

;; Get all user labels with message counts
;; Returns hash table: (hash label-name count)
;; Excludes system labels, Schemail marker, and configured exclusions
(define (get-labels-with-counts #:exclude [exclude-list '()])
  ;; Get all labels
  (define all-labels (gmail-list-labels))
  (define label-list (hash-ref all-labels 'labels '()))
  
  ;; Filter to user labels (exclude system, Schemail, and exclusion list)
  (define user-labels
    (filter (λ (label)
              (define name (hash-ref label 'name))
              (define type (hash-ref label 'type))
              (and (equal? type "user")
                   (not (equal? name "Schemail"))
                   (not (member name exclude-list))))
            label-list))
  
  ;; Fetch full details for each label to get message counts
  ;; Build hash table as we go
  (define labels-hash (make-hash))
  (for ([label user-labels])
    (define label-id (hash-ref label 'id))
    (define full-label (gmail-get-label label-id))
    (define name (hash-ref full-label 'name))
    (define count (hash-ref full-label 'messagesTotal 0))
    (when (> count 0)  ; Only include labels with messages
      (hash-set! labels-hash name count)))
  
  labels-hash)

;; Format labels hash for prompt inclusion
;; Returns formatted string: "- Label Name (N messages)\n- ..."
(define (format-labels-for-prompt labels-hash)
  (if (hash-empty? labels-hash)
      "None (first email being processed)"
      (string-join
       ;; Sort by count descending for display
       (sort
        (for/list ([(name count) (in-hash labels-hash)])
          (format "- ~a (~a message~a)"
                  name
                  count
                  (if (= count 1) "" "s")))
        string<?  ; Alphabetical for now, could sort by count
        #:key values)
       "\n")))

;; Update label hash when a new label is created
;; Increments count if exists, adds with count 1 if new
(define (update-label-hash! labels-hash label-name)
  (hash-update! labels-hash label-name add1 0))
