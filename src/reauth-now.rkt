#lang racket

(require "oauth.rkt"
         oauth2
         oauth2/storage/tokens)

(displayln "=== Starting Fresh OAuth Authorization ===")
(displayln "This will request a refresh token from Google.\n")

(displayln "The browser will open automatically.")
(displayln "If it doesn't, copy the URL and open it manually.\n")

(authorize-gmail)

(displayln "\n✅ Authorization complete!")
(displayln "Checking if we got a refresh token...\n")

;; Verify
(define user-name (getenv "USER"))
(define token (get-token user-name "gmail"))

(if (token-refresh-token token)
    (begin
      (displayln "✅ SUCCESS! Refresh token received!")
      (displayln "   Your daemon can now run indefinitely."))
    (begin
      (displayln "❌ FAILED! No refresh token received.")
      (displayln "   Did you revoke the app first at https://myaccount.google.com/permissions ?")))
