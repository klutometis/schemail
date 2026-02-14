#lang racket

;; Test LLM-based email processing

(require "oauth.rkt"
         "gmail.rkt"
         "llm.rkt"
         "../config/preferences.rkt")

;; ============================================================================
;; Test Functions
;; ============================================================================

;; Test 1: Fetch recent emails and process in dry-run mode
(define (test-dry-run #:max-results [max-results 5])
  (displayln "\n╔════════════════════════════════════════════════════════════╗")
  (displayln "║  Testing LLM Tool Calling (DRY RUN MODE)                  ║")
  (displayln "╚════════════════════════════════════════════════════════════╝\n")
  
  (get-gmail-token)
  
  (define messages-response (gmail-list-messages #:max-results max-results))
  (define message-ids (map (λ (m) (hash-ref m 'id)) 
                          (hash-ref messages-response 'messages '())))
  
  (when (empty? message-ids)
    (displayln "No messages found in inbox!")
    (exit))
  
  (displayln (format "Found ~a message(s) to process\n" (length message-ids)))
  
  (for ([id message-ids]
        [i (in-naturals 1)])
    (displayln (format "\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
    (displayln (format "MESSAGE ~a/~a" i (length message-ids)))
    (displayln (format "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
    
    (define msg (gmail-get-message id))
    
    ;; Process with LLM in dry-run mode
    (llm-process-email-dry-run msg email-assistant-prompt)
    
    (displayln "")))

;; Test 2: Process a specific message by ID (for real)
(define (test-real-processing message-id)
  (displayln "\n╔════════════════════════════════════════════════════════════╗")
  (displayln "║  Processing Email FOR REAL (LIVE MODE)                    ║")
  (displayln "╚════════════════════════════════════════════════════════════╝\n")
  
  (get-gmail-token)
  
  (define msg (gmail-get-message message-id))
  (displayln (format "From: ~a" (message-from msg)))
  (displayln (format "Subject: ~a" (message-subject msg)))
  
  (displayln "\n⚠️  WARNING: This will modify your email in Gmail!")
  (displayln "Are you SURE you want to process this email? (type 'yes' to confirm)")
  (display "> ")
  (flush-output)
  (define response (read-line))
  
  (if (equal? response "yes")
      (begin
        (displayln "\nProcessing...\n")
        (llm-process-email msg email-assistant-prompt)
        (displayln "\n✓ Done! Check Gmail to see the results."))
      (displayln "\nCancelled. No changes made.")))

;; Test 3: Interactive mode - select from recent emails
(define (test-interactive)
  (displayln "\n╔════════════════════════════════════════════════════════════╗")
  (displayln "║  Interactive Testing Mode                                 ║")
  (displayln "╚════════════════════════════════════════════════════════════╝\n")
  
  (get-gmail-token)
  
  (define messages-response (gmail-list-messages #:max-results 10))
  (define messages (hash-ref messages-response 'messages '()))
  
  (when (empty? messages)
    (displayln "No messages found in inbox!")
    (exit))
  
  (displayln "Recent emails:\n")
  
  ;; Fetch and display message details
  (define message-details
    (for/list ([msg messages]
               [i (in-naturals 1)])
      (define id (hash-ref msg 'id))
      (define full-msg (gmail-get-message id))
      (displayln (format "~a. From: ~a" i (message-from full-msg)))
      (displayln (format "   Subject: ~a" (message-subject full-msg)))
      (displayln (format "   Snippet: ~a\n" (message-snippet full-msg)))
      (cons i full-msg)))
  
  (displayln "Enter a number to process that email (dry-run), or 'q' to quit:")
  (display "> ")
  (flush-output)
  (define choice (read-line))
  
  (cond
    [(equal? choice "q")
     (displayln "Goodbye!")]
    [(string->number choice)
     (define num (string->number choice))
     (define selected (assoc num message-details))
     (if selected
         (begin
           (displayln "\n")
           (llm-process-email-dry-run (cdr selected) email-assistant-prompt))
         (displayln "Invalid choice!"))]
    [else
     (displayln "Invalid choice!")]))

;; Test 4: Batch test with summary
(define (test-batch #:max-results [max-results 20])
  (displayln "\n╔════════════════════════════════════════════════════════════╗")
  (displayln "║  Batch Testing with Summary                                ║")
  (displayln "╚════════════════════════════════════════════════════════════╝\n")
  
  (get-gmail-token)
  
  (define messages-response (gmail-list-messages #:max-results max-results))
  (define message-ids (map (λ (m) (hash-ref m 'id)) 
                          (hash-ref messages-response 'messages '())))
  
  (when (empty? message-ids)
    (displayln "No messages found in inbox!")
    (exit))
  
  (displayln (format "Processing ~a messages...\n" (length message-ids)))
  
  (define action-count 0)
  (define notification-count 0)
  (define recruiter-count 0)
  (define other-count 0)
  
  (for ([id message-ids]
        [i (in-naturals 1)])
    (displayln (format "\n[~a/~a] Processing..." i (length message-ids)))
    
    (define msg (gmail-get-message id))
    (displayln (format "Subject: ~a" (message-subject msg)))
    
    (define tool-calls (llm-process-email-dry-run msg email-assistant-prompt))
    
    ;; Count labels
    (for ([call tool-calls])
      (when (equal? (hash-ref call 'name) "apply_label")
        (define label (hash-ref (hash-ref call 'input) 'label_name))
        (cond
          [(equal? label "action") (set! action-count (+ action-count 1))]
          [(equal? label "notification") (set! notification-count (+ notification-count 1))]
          [(equal? label "recruiter") (set! recruiter-count (+ recruiter-count 1))]
          [else (set! other-count (+ other-count 1))]))))
  
  ;; Print summary
  (displayln "\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  (displayln "SUMMARY")
  (displayln "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  (displayln (format "Total emails processed: ~a" (length message-ids)))
  (displayln (format "  - Action: ~a" action-count))
  (displayln (format "  - Notification: ~a" notification-count))
  (displayln (format "  - Recruiter: ~a" recruiter-count))
  (displayln (format "  - Other: ~a" other-count))
  (displayln ""))

;; ============================================================================
;; Main Entry Point
;; ============================================================================

(define (main)
  (displayln "
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║  LLM Email Processing Test Suite                          ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

Choose a test mode:

  1. Dry-run on recent emails (safe, no changes)
  2. Interactive mode (choose an email to test)
  3. Batch test with summary (tests many emails)
  4. Process one email FOR REAL (live mode, makes changes!)
  
  q. Quit
")
  
  (display "Enter your choice: ")
  (flush-output)
  (define choice (read-line))
  
  (match choice
    ["1" (test-dry-run #:max-results 5)]
    ["2" (test-interactive)]
    ["3" (test-batch #:max-results 20)]
    ["4" 
     (displayln "\nEnter the message ID to process:")
     (display "> ")
     (flush-output)
     (define msg-id (read-line))
     (test-real-processing msg-id)]
    ["q" (displayln "Goodbye!")]
    [else 
     (displayln "\nInvalid choice!")
     (main)]))

;; Run main if executed directly
(module+ main
  (main))
