#lang racket

;; Test the filter DSL

(require "filters.rkt"
         "gmail.rkt")

(displayln "=== Testing Email Filter DSL ===\n")

;; Define some test filters
(define test-filters
  '(
    ;; Match Anthropic receipts
    (filter (and (from "anthropic.com")
                 (subject "receipt"))
            (label "Receipt/Anthropic")
            (mark-read))
    
    ;; Match newsletters
    (filter (subject "newsletter")
            (label "Newsletter")
            (archive))
    ))

;; Fetch recent messages
(displayln "Fetching recent messages...")
(define messages-response (gmail-list-messages #:max-results 10))
(define message-ids (hash-ref messages-response 'messages '()))

(displayln (format "Found ~a messages\n" (length message-ids)))

;; Fetch full message details
(define messages
  (for/list ([msg-id message-ids])
    (gmail-get-message (hash-ref msg-id 'id))))

;; Apply filters
(displayln "Applying filters...\n")
(apply-filters messages test-filters)

(displayln "\n=== Filter test complete! ===")
