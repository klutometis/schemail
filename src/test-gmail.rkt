#lang racket

;; Test Gmail API wrapper functions

(require "gmail.rkt")

(displayln "=== Testing Gmail API Wrapper ===\n")

;; Test 1: List recent messages
(displayln "Test 1: Fetching 5 recent messages...")
(define messages-response (gmail-list-messages #:max-results 5))
(define messages (hash-ref messages-response 'messages '()))
(displayln (format "Found ~a messages" (length messages)))

;; Test 2: Get full message details
(when (not (empty? messages))
  (displayln "\nTest 2: Fetching details for first message...")
  (define first-msg-id (hash-ref (first messages) 'id))
  (define full-msg (gmail-get-message first-msg-id))
  
  (displayln (format "Subject: ~a" (message-subject full-msg)))
  (displayln (format "From: ~a" (message-from full-msg)))
  (displayln (format "Date: ~a" (message-date full-msg)))
  (displayln (format "Snippet: ~a" (message-snippet full-msg))))

;; Test 3: Find a label
(displayln "\nTest 3: Finding INBOX label...")
(define inbox-label-id (gmail-find-label-by-name "INBOX"))
(displayln (format "INBOX label ID: ~a" inbox-label-id))

;; Test 4: List all labels
(displayln "\nTest 4: Listing all labels...")
(define labels-response (gmail-list-labels))
(define labels (hash-ref labels-response 'labels '()))
(displayln (format "Total labels: ~a" (length labels)))
(for ([label (take labels (min 10 (length labels)))])
  (displayln (format "  - ~a (id: ~a)" 
                     (hash-ref label 'name)
                     (hash-ref label 'id))))

(displayln "\n=== All tests passed! ===")
