#lang racket

;; Quick test of OAuth flow

(require "oauth.rkt")

(displayln "=== Gmail OAuth Test ===")
(displayln "This will open your browser for authorization.")
(displayln "Make sure Gmail API is enabled in your GCP project!")
(displayln "")

;; Start OAuth flow
(define token (authorize-gmail))

(displayln "")
(displayln "=== Testing Gmail API ===")
(displayln "Fetching your Gmail labels...")

;; Test API call - list labels
(define labels (gmail-api-request "labels"))
(displayln (format "Found ~a labels:" (length (hash-ref labels 'labels))))
(for ([label (hash-ref labels 'labels)])
  (displayln (format "  - ~a" (hash-ref label 'name))))

(displayln "")
(displayln "Success! OAuth and Gmail API are working!")
