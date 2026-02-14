#lang racket

;; LLM-based email processing with Claude API tool calling

(require "gmail.rkt"
         json
         net/url
         net/http-easy)

(provide llm-process-email
         llm-process-email-dry-run)

;; ============================================================================
;; Configuration
;; ============================================================================

(define CLAUDE-API-URL "https://api.anthropic.com/v1/messages")
(define CLAUDE-MODEL "claude-sonnet-4-20250514")  ; Sonnet 4.5
(define CLAUDE-MODEL-HAIKU "claude-3-5-haiku-20241022")  ; Haiku 4.5 fallback
(define ANTHROPIC-API-KEY (getenv "ANTHROPIC_API_KEY"))

(unless ANTHROPIC-API-KEY
  (error "ANTHROPIC_API_KEY environment variable not set"))

;; ============================================================================
;; Tool Definitions
;; ============================================================================

(define TOOLS
  '(#hasheq((name . "apply_label")
            (description . "Apply a Gmail label to this email. Use one of: receipt, shipping, social, newsletter, notification.")
            (input_schema . #hasheq((type . "object")
                                    (properties . #hasheq((label_name . #hasheq((type . "string")
                                                                                (description . "Label name: receipt, shipping, social, newsletter, or notification")))))
                                    (required . ("label_name")))))
    #hasheq((name . "archive_email")
            (description . "Remove this email from the inbox (archives it). Use for emails that don't need immediate attention.")
            (input_schema . #hasheq((type . "object")
                                    (properties . #hasheq()))))
    #hasheq((name . "star_email")
            (description . "Star this email to mark it as important or requiring follow-up.")
            (input_schema . #hasheq((type . "object")
                                    (properties . #hasheq()))))
    #hasheq((name . "mark_as_read")
            (description . "Mark this email as read. Use for notifications or automated messages that don't require action.")
            (input_schema . #hasheq((type . "object")
                                    (properties . #hasheq()))))
    #hasheq((name . "do_nothing")
            (description . "Leave the email as-is in the inbox. Use when the email needs human review or you're unsure.")
            (input_schema . #hasheq((type . "object")
                                    (properties . #hasheq((reason . #hasheq((type . "string")
                                                                            (description . "Why this email should stay in inbox")))))
                                    (required . ("reason")))))))

;; ============================================================================
;; Email Formatting
;; ============================================================================

;; Format email content for LLM prompt
(define (format-email-for-llm message)
  (define from (or (message-from message) "Unknown"))
  (define to (or (message-header message "To") "Unknown"))
  (define subject (or (message-subject message) "(no subject)"))
  (define snippet (or (message-snippet message) "(no content)"))
  (define date (or (message-date message) "Unknown"))
  
  (format "From: ~a\nTo: ~a\nDate: ~a\nSubject: ~a\n\nContent:\n~a"
          from to date subject snippet))

;; ============================================================================
;; Claude API
;; ============================================================================

;; Call Claude API with tool calling
(define (claude-api-call message preferences #:model [model CLAUDE-MODEL])
  (define email-text (format-email-for-llm message))
  
  (define request-body
    (hasheq 'model model
            'max_tokens 1024
            'tools TOOLS
            'messages (list (hasheq 'role "user"
                                    'content (format "~a\n\nEmail to process:\n\n~a"
                                                    preferences
                                                    email-text)))))
  
  (displayln "\n=== Calling Claude API ===")
  (displayln (format "Model: ~a" model))
  
  (define response
    (post CLAUDE-API-URL
          #:headers (hash 'x-api-key ANTHROPIC-API-KEY
                         'anthropic-version "2023-06-01"
                         'content-type "application/json")
          #:data (jsexpr->string request-body)))
  
  (unless (= (response-status-code response) 200)
    (error 'claude-api-call
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
  
  ;; Extract tool calls from response
  (define content (hash-ref response-json 'content '()))
  (define tool-calls
    (filter (λ (item) (equal? (hash-ref item 'type #f) "tool_use"))
            content))
  
  (displayln (format "Received ~a tool call(s)" (length tool-calls)))
  
  tool-calls)

;; ============================================================================
;; Tool Execution
;; ============================================================================

;; Execute a single tool call
(define (execute-tool-call message tool-call #:dry-run? [dry-run? #f])
  (define tool-name (hash-ref tool-call 'name))
  (define tool-input (hash-ref tool-call 'input (hasheq)))
  (define message-id (hash-ref message 'id))
  
  (displayln (format "\n  Tool: ~a" tool-name))
  (displayln (format "  Input: ~a" tool-input))
  
  (when dry-run?
    (displayln "  [DRY RUN - not executing]")
    (void))
  
  (unless dry-run?
    (match tool-name
      ["apply_label"
       (define raw-label-name (hash-ref tool-input 'label_name))
       
       ;; Add Schemail/ prefix (capitalized) if not already present
       (define label-name
         (if (or (string-prefix? raw-label-name "Schemail/")
                 (string-prefix? raw-label-name "schemail/"))
             raw-label-name
             (string-append "Schemail/" 
                           ;; Capitalize first letter of label
                           (string-append (string-upcase (substring raw-label-name 0 1))
                                         (substring raw-label-name 1)))))
       
       (displayln (format "  → Applying label: ~a (model suggested: ~a)" 
                         label-name raw-label-name))
       
       ;; Find or create label
       (define label-id (gmail-find-label-by-name label-name))
       (unless label-id
         (displayln (format "  → Creating new label: ~a" label-name))
         (define new-label (gmail-create-label label-name))
         (set! label-id (hash-ref new-label 'id)))
       
       ;; Apply label
       (gmail-modify-message message-id #:add-labels (list label-id))
       (displayln "  ✓ Label applied")
       
       ;; Auto-archive: any schemail/ label means it's automated
       (displayln "  → Auto-archiving (schemail/ label detected)")
       (gmail-modify-message message-id #:remove-labels '("INBOX"))
       (displayln "  ✓ Archived")]
      
      ["archive_email"
       (displayln "  → Archiving email (removing from INBOX)")
       (gmail-modify-message message-id #:remove-labels '("INBOX"))
       (displayln "  ✓ Archived")]
      
      ["star_email"
       (displayln "  → Starring email")
       (gmail-modify-message message-id #:add-labels '("STARRED"))
       (displayln "  ✓ Starred")]
      
      ["mark_as_read"
       (displayln "  → Marking as read")
       (gmail-modify-message message-id #:remove-labels '("UNREAD"))
       (displayln "  ✓ Marked as read")]
      
      ["do_nothing"
       (define reason (hash-ref tool-input 'reason "No reason given"))
       (displayln (format "  → Leaving in inbox: ~a" reason))
       (displayln "  ✓ No action taken")]
      
      [else
       (displayln (format "  ✗ Unknown tool: ~a" tool-name))])))

;; Execute all tool calls
(define (execute-tool-calls message tool-calls #:dry-run? [dry-run? #f])
  (displayln (format "\n=== Executing ~a tool call(s) ===" (length tool-calls)))
  
  (for-each (λ (tool-call)
              (execute-tool-call message tool-call #:dry-run? dry-run?))
            tool-calls)
  
  (displayln "\n=== Done ==="))

;; ============================================================================
;; Public API
;; ============================================================================

;; Process an email with LLM (main entry point)
(define (llm-process-email message preferences #:dry-run? [dry-run? #f] #:model [model CLAUDE-MODEL])
  (displayln "\n========================================")
  (displayln "LLM Email Processing")
  (displayln "========================================")
  (displayln (format "From: ~a" (message-from message)))
  (displayln (format "Subject: ~a" (message-subject message)))
  (displayln (format "Mode: ~a" (if dry-run? "DRY RUN" "LIVE")))
  
  (define tool-calls (claude-api-call message preferences #:model model))
  
  (if (empty? tool-calls)
      (begin
        (displayln "\nNo tool calls returned by Claude (model may have responded with text only)")
        '())
      (begin
        (execute-tool-calls message tool-calls #:dry-run? dry-run?)
        tool-calls)))

;; Convenience wrapper for dry-run
(define (llm-process-email-dry-run message preferences #:model [model CLAUDE-MODEL])
  (llm-process-email message preferences #:dry-run? #t #:model model))
