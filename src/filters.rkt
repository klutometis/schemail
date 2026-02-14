#lang racket

;; Email filter DSL - elegant S-expression rules

(require "gmail.rkt"
         json
         (only-in "llm.rkt" llm-process-email))

;; ============================================================================
;; Filter DSL
;; ============================================================================

;; A filter is: (filter condition action ...)
;; 
;; Conditions:
;;   (from pattern)           - match sender
;;   (to pattern)             - match recipient  
;;   (subject pattern)        - match subject
;;   (body pattern)           - match body/snippet
;;   (has-label label)        - has specific label
;;   (and cond ...)           - all conditions match
;;   (or cond ...)            - any condition matches
;;   (not cond)               - condition doesn't match
;;   (always)                 - always matches (useful for fallback filters)
;;   (llm-match prompt)       - ask LLM if email matches
;;
;; Actions:
;;   (label name)             - apply label
;;   (archive)                - remove from inbox
;;   (mark-read)              - mark as read
;;   (star)                   - star the message
;;   (skip)                   - stop processing further filters
;;   (llm-agent preferences)  - use LLM to decide actions

;; ============================================================================
;; Condition Evaluation
;; ============================================================================

;; Evaluate a condition against a message
(define (eval-condition condition message)
  (match condition
    ;; Simple string matching
    [`(from ,pattern)
     (string-contains? (or (message-from message) "") pattern)]
    
    [`(to ,pattern)
     (string-contains? (or (message-header message "To") "") pattern)]
    
    [`(subject ,pattern)
     (string-contains? (or (message-subject message) "") pattern)]
    
    [`(subject-contains ,pattern)
     (string-contains? (or (message-subject message) "") pattern)]
    
    [`(body ,pattern)
     (string-contains? (or (message-snippet message) "") pattern)]
    
    [`(has-label ,label-name)
     (define label-id (gmail-find-label-by-name label-name))
     (and label-id (message-has-label? message label-id))]
    
    ;; Logical operators
    [`(and ,conds ...)
     (andmap (λ (c) (eval-condition c message)) conds)]
    
    [`(or ,conds ...)
     (ormap (λ (c) (eval-condition c message)) conds)]
    
    [`(not ,cond)
     (not (eval-condition cond message))]
    
    ;; Always matches (for fallback filters)
    [`(always)
     #t]
    
    ;; LLM matching (TODO: implement)
    [`(llm-match ,prompt)
     (error "LLM matching not yet implemented")]
    
    [else
     (error "Unknown condition:" condition)]))

;; Helper: case-insensitive substring match
(define (string-contains? haystack needle)
  (and (string? haystack)
       (string? needle)
       (regexp-match? (regexp-quote needle) haystack)))

;; ============================================================================
;; Action Execution
;; ============================================================================

;; Execute actions on a message
;; Returns: 'skip if we should stop processing, #f otherwise
;; message can be either a message ID (string) or a full message hash
(define (exec-actions actions message-or-id)
  ;; Extract message ID and full message
  (define message-id (if (hash? message-or-id)
                         (hash-ref message-or-id 'id)
                         message-or-id))
  (define full-message (if (hash? message-or-id)
                           message-or-id
                           (gmail-get-message message-or-id)))
  
  (for/fold ([should-skip? #f])
            ([action actions]
             #:break should-skip?)
    (match action
      [`(label ,name)
       (define label-id (or (gmail-find-label-by-name name)
                            (let ()
                              (displayln (format "Creating label: ~a" name))
                              (define resp (gmail-create-label name))
                              (hash-ref resp 'id))))
       (gmail-modify-message message-id #:add-labels (list label-id))
       (displayln (format "  → Applied label: ~a" name))
       #f]
      
      [`(archive)
       (define inbox-id (gmail-find-label-by-name "INBOX"))
       (gmail-modify-message message-id #:remove-labels (list inbox-id))
       (displayln "  → Archived")
       #f]
      
      [`(mark-read)
       ;; UNREAD is a system label with ID "UNREAD"
       (with-handlers ([exn:fail? (λ (e) 
                                     (displayln (format "  → Failed to mark read: ~a" 
                                                       (exn-message e))))])
         (gmail-modify-message message-id #:remove-labels (list "UNREAD"))
         (displayln "  → Marked as read"))
       #f]
      
      [`(star)
       (gmail-modify-message message-id #:add-labels (list "STARRED"))
       (displayln "  → Starred")
       #f]
      
      [`(skip)
       (displayln "  → Skipping further filters")
       #t]
      
      [`(llm-agent ,preferences)
       (displayln "  → Calling LLM agent...")
       (llm-process-email full-message preferences #:dry-run? #f)
       #f]
      
      [else
       (error "Unknown action:" action)])))

;; Execute actions with dry-run support
(define (exec-actions-dry-run actions message #:dry-run? [dry-run? #f])
  (if dry-run?
      (begin
        (displayln "\n  [DRY RUN MODE - not executing actions]")
        (for ([action actions])
          (match action
            ;; Special case: llm-agent should actually run in dry-run to show decisions
            [`(llm-agent ,preferences)
             (displayln "    Calling LLM to see what it would do...")
             (llm-process-email message preferences #:dry-run? #t)]
            ;; Everything else just show what would happen
            [else
             (displayln (format "    Would execute: ~a" action))]))
        #f)
      (exec-actions actions (hash-ref message 'id))))

;; ============================================================================
;; Filter Processing
;; ============================================================================

;; Process a single message through all filters
;; Returns: #t if we should stop processing (hit a skip action)
(define (process-message-with-filters message filters #:dry-run? [dry-run? #f])
  (define message-id (hash-ref message 'id))
  (define subject (message-subject message))
  (define from (message-from message))
  
  (displayln (format "\nProcessing: ~a" (or subject "(no subject)")))
  (displayln (format "From: ~a" (or from "(unknown)")))
  
  (for/fold ([should-stop? #f])
            ([filter filters]
             #:break should-stop?)
    (match filter
      [`(filter ,condition ,actions ...)
       (if (eval-condition condition message)
           (begin
             (displayln (format "  ✓ Matched filter: ~a" condition))
             (if dry-run?
                 (exec-actions-dry-run actions message #:dry-run? #t)
                 (exec-actions actions message-id)))
           #f)]
      [else
       (error "Invalid filter format:" filter)])))

;; Process all messages with filters
(define (apply-filters messages filters #:dry-run? [dry-run? #f])
  (for ([message messages])
    (process-message-with-filters message filters #:dry-run? dry-run?)))

;; Module exports
(provide eval-condition
         exec-actions
         exec-actions-dry-run
         process-message-with-filters
         apply-filters)
