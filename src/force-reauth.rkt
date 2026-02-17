#lang racket

;; Force re-authorization to get a refresh token

(require "oauth.rkt"
         oauth2/storage/tokens)

(displayln "=== Force Re-authorization ===\n")

(displayln "This will delete your existing token and force a fresh authorization.")
(displayln "Google should provide a refresh token on fresh authorization.\n")

(define user-name (getenv "USER"))

;; Delete existing token
(displayln "Deleting existing token...")
(define token-file (build-path (find-system-path 'home-dir) ".oauth2.rkt" "tokens"))

(when (file-exists? token-file)
  (displayln (format "  Backing up to ~a.backup" token-file))
  (copy-file token-file (string-append (path->string token-file) ".backup") #t)
  (displayln (format "  Deleting ~a" token-file))
  (delete-file token-file))

(displayln "\n✓ Token deleted. Starting fresh authorization...\n")
(displayln "IMPORTANT: You must authorize in your browser.")
(displayln "After authorization completes, check that you got a refresh token.\n")

;; This will trigger fresh authorization
(define new-token (authorize-gmail))

(displayln "\n=== Checking new token ===")
(if (token-refresh-token new-token)
    (displayln "✅ SUCCESS! Got refresh token. Your daemon should now work.")
    (displayln "❌ FAILED! Still no refresh token. Google may need app revocation."))
