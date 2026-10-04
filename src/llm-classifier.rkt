#lang racket

;; Structured output classifier for email processing
;; Uses Claude API with structured output (NOT tool calling)

(require "gmail.rkt"
         "label-utils.rkt"
         json
         net/url
         net/http-easy)

(provide classify-email
         classify-email-dry-run
         apply-classification
         current-model)

;; ============================================================================
;; Configuration
;; ============================================================================

(define CLAUDE-API-URL "https://api.anthropic.com/v1/messages")
(define DEFAULT-CLAUDE-MODEL "claude-haiku-4-5")  ; Haiku 4.5 (cheap, default)
(define ANTHROPIC-API-KEY (getenv "ANTHROPIC_API_KEY"))

;; Model parameter - can be overridden by caller
(define current-model (make-parameter DEFAULT-CLAUDE-MODEL))

(unless ANTHROPIC-API-KEY
  (error "ANTHROPIC_API_KEY environment variable not set"))

;; ============================================================================
;; Classification Schema
;; ============================================================================

;; JSON schema for structured classification output
(define CLASSIFICATION-SCHEMA
  (hasheq 'type "object"
          'properties (hasheq 'label (hasheq 'type "string"
                                             'description "Short category name for this email")
                              'should_archive (hasheq 'type "boolean"
                                                      'description "Should this email be removed from inbox?")
                              'rationale (hasheq 'type "string"
                                                 'description "Brief explanation of the classification decision"))
          'required '("label" "should_archive" "rationale")
          'additionalProperties #f))

;; ============================================================================
;; Email Formatting
;; ============================================================================

;; Format email content for LLM prompt
(define (format-email-for-llm message)
  (define from (or (message-from message) "Unknown"))
  (define to (or (message-header message "To") "Unknown"))
  (define cc (message-header message "Cc"))
  (define subject (or (message-subject message) "(no subject)"))
  (define snippet (or (message-snippet message) "(no content)"))
  (define date (or (message-date message) "Unknown"))
  
  ;; Header facts the model cannot see in the snippet. These are the
  ;; strongest noise/signal discriminators we have, so state them plainly.
  (define bulk-markers
    (filter values
            (list (and (message-header message "List-Unsubscribe") "List-Unsubscribe")
                  (and (message-header message "List-Id") "List-Id")
                  (let ([p (message-header message "Precedence")])
                    (and p (format "Precedence: ~a" p)))
                  (let ([a (message-header message "Auto-Submitted")])
                    (and a (not (string-ci=? a "no")) (format "Auto-Submitted: ~a" a))))))
  (define corresponded (sender-corresponded? from))
  
  (format (string-append
           "From: ~a\nTo: ~a\n~aDate: ~a\nSubject: ~a\n\n"
           "Bulk/automation headers: ~a\n"
           "Peter has emailed this sender before: ~a\n\n"
           "Content:\n~a")
          from to (if cc (format "Cc: ~a\n" cc) "") date subject
          (if (empty? bulk-markers) "none" (string-join bulk-markers ", "))
          (case corresponded [(#t) "yes"] [(#f) "no"] [else "unknown"])
          snippet))

;; Who the inbox belongs to: job, projects, family situation. Kept out of the
;; (public) repo in config/personal-context.txt, which is gitignored; see
;; config/personal-context.example.txt. Read once, empty if absent.
(define personal-context
  (let ([cached #f])
    (λ ()
      (unless cached
        ;; Relative to the working directory, like config/credentials.json.
        (define f (build-path "config" "personal-context.txt"))
        (set! cached (if (file-exists? f)
                         (string-append "Context: " (string-trim (file->string f)) "\n")
                         "")))
      cached)))

;; Has Peter ever sent mail to this address? One Gmail search per distinct
;; sender, cached for the life of the process (the daemon runs for weeks; the
;; answer only ever flips no -> yes, and a stale "no" costs one archive).
(define correspondent-cache (make-hash))

(define (sender-address from)
  (define m (regexp-match #rx"<([^>]+)>" from))
  (string-downcase (string-trim (if m (cadr m) from))))

(define (sender-corresponded? from)
  (define addr (sender-address from))
  (define answer
    (cond
      [(not (regexp-match? #rx"^[^@ ]+@[^@ ]+$" addr)) 'unknown]
      [(hash-ref correspondent-cache addr #f) => values]
      [else
       (define a
         (with-handlers ([exn:fail? (λ (e) 'unknown)])  ; transient: don't cache
           (define r (gmail-list-messages #:query (format "in:sent to:~a" addr)
                                          #:max-results 1))
           (if (pair? (hash-ref r 'messages '())) 'yes 'no)))
       (unless (eq? a 'unknown) (hash-set! correspondent-cache addr a))
       a]))
  (case answer [(yes) #t] [(no) #f] [else 'unknown]))

;; ============================================================================
;; Claude API with Structured Output
;; ============================================================================

;; Check if an exception is a transient error that should be retried
(define (transient-api-error? exn)
  (define msg (exn-message exn))
  (or (regexp-match? #rx"timed out" msg)           ; Catches "connect timed out", "request timed out", "Connection timed out"
      (regexp-match? #rx"[Cc]onnection reset" msg)
      (regexp-match? #rx"[Cc]onnection refused" msg)
      (regexp-match? #rx"Network is unreachable" msg)
      (regexp-match? #rx"error reading from stream" msg)))

;; Call Claude API with structured output
(define (claude-classify message prompt labels-hash)
  (define email-text (format-email-for-llm message))
  
  ;; Format existing labels and inject into prompt
  (define formatted-labels (format-labels-for-prompt labels-hash))
  (define final-prompt
    (string-replace (string-replace prompt "{existing_labels}" formatted-labels)
                    "{personal_context}" (personal-context)))
  
  ;; Debug: show labels being sent
  (unless (hash-empty? labels-hash)
    (displayln "\nExisting labels being provided to model:")
    (displayln formatted-labels))
  
  ;; Build request with output_config for structured outputs
  (define request-body
    (hasheq 'model (current-model)
            'max_tokens 1024
            'output_config (hasheq 'format (hasheq 'type "json_schema"
                                                    'schema CLASSIFICATION-SCHEMA))
            'messages (list (hasheq 'role "user"
                                    'content (format "~a\n\nEmail to classify:\n\n~a"
                                                    final-prompt
                                                    email-text)))))
  
  (displayln "\n=== Calling Claude API (Classifier) ===")
  (displayln (format "Model: ~a" (current-model)))
  
  ;; Retry loop with exponential backoff for transient errors
  (define (attempt retry-count max-retries base-delay)
    (with-handlers ([exn:fail?
                     (λ (exn)
                       (if (and (transient-api-error? exn)
                                (< retry-count max-retries))
                           (let ([delay (* base-delay (expt 2 retry-count))])
                             (displayln (format "⚠ API error: ~a" (exn-message exn)))
                             (displayln (format "→ Retrying in ~a seconds (attempt ~a/~a)..."
                                               delay
                                               (+ retry-count 1)
                                               max-retries))
                             (sleep delay)
                             (attempt (+ retry-count 1) max-retries base-delay))
                           (raise exn)))])
      (post CLAUDE-API-URL
            #:headers (hash 'x-api-key ANTHROPIC-API-KEY
                           'anthropic-version "2023-06-01"
                           'content-type "application/json")
            #:data (jsexpr->string request-body))))
  
  (define response (attempt 0 3 2))  ;; max 3 retries, 2s base delay
  
  (unless (= (response-status-code response) 200)
    (error 'claude-classify
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
  
  ;; Extract classification from response content
  (define content (hash-ref response-json 'content '()))
  (when (empty? content)
    (error 'claude-classify "No content in API response"))
  
  (define first-content (car content))
  (define content-type (hash-ref first-content 'type #f))
  
  (unless (equal? content-type "text")
    (error 'claude-classify "Expected text content, got: ~a" content-type))
  
  (define classification-text (hash-ref first-content 'text))
  
  ;; Parse JSON from text response
  ;; With output_config, Claude returns valid JSON in the text field
  (define classification
    (with-handlers ([exn:fail? (λ (e)
                                 (displayln (format "Failed to parse JSON: ~a" classification-text))
                                 (error 'claude-classify "Invalid JSON response from Claude: ~a" (exn-message e)))])
      (string->jsexpr classification-text)))
  
  (displayln "\n=== Classification Result ===")
  (displayln (format "Label: ~a" (hash-ref classification 'label)))
  (displayln (format "Archive: ~a" (hash-ref classification 'should_archive)))
  (displayln (format "Rationale: ~a" (hash-ref classification 'rationale)))
  
  classification)

;; ============================================================================
;; Classification Application
;; ============================================================================

;; Apply classification results to Gmail message
(define (apply-classification message classification labels-hash #:dry-run? [dry-run? #f])
  (define label (hash-ref classification 'label))
  (define should-archive? (hash-ref classification 'should_archive))
  (define rationale (hash-ref classification 'rationale))
  (define message-id (hash-ref message 'id))
  
  (displayln "\n=== Applying Classification ===")
  (displayln (format "Label: ~a" label))
  (displayln (format "Archive: ~a" should-archive?))
  (displayln (format "Rationale: ~a" rationale))
  
  ;; Resolve label via LLM (dedup + proper casing) with normalize fallback
  (define content-label (resolve-canonical-label label labels-hash))
  (displayln (format "Content label: ~a" content-label))
  
  (when dry-run?
    (displayln "\n[DRY RUN - not executing]")
    (void))
  
  (unless dry-run?
    ;; Ensure Schemail marker exists and is hidden
    (define schemail-marker-id (ensure-schemail-marker))
    
    ;; Apply content label + Schemail marker
    (apply-content-and-marker-labels message-id content-label schemail-marker-id)
    
    ;; Archive if model says so
    (when should-archive?
      (archive-message message-id))
    
    (displayln "\n=== Done ===")))

;; ============================================================================
;; Public API
;; ============================================================================

;; Classify an email and return structured result
;; Updates labels-hash when new labels are created
;; Returns: (values label should-archive? rationale)
(define (classify-email message prompt labels-hash #:dry-run? [dry-run? #f])
  (displayln "\n========================================")
  (displayln "LLM Email Classification")
  (displayln "========================================")
  (displayln (format "From: ~a" (message-from message)))
  (displayln (format "Subject: ~a" (message-subject message)))
  (displayln (format "Mode: ~a" (if dry-run? "DRY RUN" "LIVE")))
  
  (define classification (claude-classify message prompt labels-hash))
  (apply-classification message classification labels-hash #:dry-run? dry-run?)
  
  ;; Update labels hash with the label we just used (unless dry-run)
  (unless dry-run?
    (define label (hash-ref classification 'label))
    (define resolved-label (resolve-canonical-label label labels-hash))
    (update-label-hash! labels-hash resolved-label))
  
  ;; Return as values tuple
  (values (hash-ref classification 'label)
          (hash-ref classification 'should_archive)
          (hash-ref classification 'rationale)))

;; Convenience wrapper for dry-run
(define (classify-email-dry-run message prompt labels-hash)
  (classify-email message prompt labels-hash #:dry-run? #t))
