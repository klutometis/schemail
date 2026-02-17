#lang racket

;; Diagnose token storage issues

(require oauth2
         oauth2/storage/tokens)

(displayln "=== Token Diagnostics ===\n")

(define user-name (getenv "USER"))
(displayln (format "User: ~a" user-name))

;; Try to load token with error handling
(define token
  (with-handlers ([exn:fail? (λ (e)
                               (displayln "\n❌ ERROR loading token:")
                               (displayln (format "   ~a" (exn-message e)))
                               #f)])
    (get-token user-name "gmail")))

(if token
    (let ([time-left (- (token-expires token) (current-seconds))])
      (displayln "\n✓ Token loaded successfully")
      (displayln (format "  Access token: ~a" 
                        (if (token-access-token token) "present" "MISSING")))
      (displayln (format "  Refresh token: ~a" 
                        (if (token-refresh-token token) "present" "MISSING")))
      (displayln (format "  Token type: ~a" (token-type token)))
      (displayln (format "  Expires: ~a" (token-expires token)))
      (displayln (format "  Current time: ~a" (current-seconds)))
      (displayln (format "  Time until expiry: ~a seconds (~a minutes)" 
                        time-left 
                        (exact->inexact (/ time-left 60))))
      (displayln (format "  Expired: ~a" (if (< time-left 0) "YES" "NO")))
      
      (if (token-refresh-token token)
          (displayln "\n✓ Refresh token is present - automatic refresh should work")
          (displayln "\n❌ NO REFRESH TOKEN - You must re-authorize to get one!")))
    (displayln "\n❌ Could not load token"))
