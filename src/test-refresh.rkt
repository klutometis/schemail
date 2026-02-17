#lang racket

(require "oauth.rkt"
         oauth2
         oauth2/storage/tokens)

(displayln "=== Testing Token Refresh ===\n")

(define user-name (getenv "USER"))
(displayln "Loading current token...")
(define token (get-token user-name "gmail"))

(displayln "Current token:")
(displayln (format "  Expires: ~a" (token-expires token)))
(displayln (format "  Current: ~a" (current-seconds)))
(define time-left (- (token-expires token) (current-seconds)))
(displayln (format "  Time left: ~a seconds (~a min)" time-left (/ time-left 60.0)))
(displayln (format "  Has refresh: ~a" (if (token-refresh-token token) "YES" "NO")))

(displayln "\nCalling get-gmail-token (should refresh if needed)...")
(define new-token (get-gmail-token))

(displayln "✅ Success!")
(displayln (format "  New expires: ~a" (token-expires new-token)))
(define new-time-left (- (token-expires new-token) (current-seconds)))
(displayln (format "  New time left: ~a seconds (~a min)" new-time-left (/ new-time-left 60.0)))
