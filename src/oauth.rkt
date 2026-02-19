#lang racket

;; Gmail OAuth2 Flow using simple-oauth2 package
;; Much better than rolling our own!

(require oauth2
         oauth2/client
         oauth2/client/flow
         oauth2/storage/clients
         oauth2/storage/tokens
         oauth2/storage/config
         oauth2/private/redirect-server
         json
         net/url
         net/uri-codec
         racket/async-channel)

;; Gmail API scopes
(define gmail-scopes
  (list "https://www.googleapis.com/auth/gmail.readonly"
        "https://www.googleapis.com/auth/gmail.modify"
        "https://www.googleapis.com/auth/gmail.labels"
        "https://www.googleapis.com/auth/userinfo.profile"))  ; For People API

;; Load credentials from config file
(define (load-credentials-from-file)
  (define creds-file "config/credentials.json")
  (unless (file-exists? creds-file)
    (error "Missing credentials file. Copy config/credentials.json.example and fill in your OAuth credentials."))
  
  (define creds (call-with-input-file creds-file read-json))
  (values (hash-ref creds 'client_id)
          (hash-ref creds 'client_secret)
          (hash-ref creds 'redirect_uri)))

;; Create Gmail client configuration
(define (make-gmail-client)
  (define-values (client-id client-secret redirect-uri) (load-credentials-from-file))
  
  ;; client struct: (service-name auth-uri token-uri revoke-uri introspect-uri id secret)
  (client
   "gmail"  ; service-name
   (url->string (string->url "https://accounts.google.com/o/oauth2/v2/auth"))  ; authorization-uri
   (url->string (string->url "https://oauth2.googleapis.com/token"))           ; token-uri
   #f       ; revoke-uri (optional)
   #f       ; introspect-uri (optional)
   client-id
   client-secret))

;; Build Gmail-specific auth URL with offline access
(define (make-gmail-auth-url client-id scopes state)
  (define params
    `((client_id . ,client-id)
      (redirect_uri . "http://localhost:8080/oauth/authorization")
      (response_type . "code")
      (scope . ,(string-join scopes " "))
      (access_type . "offline")  ; Request refresh token
      (prompt . "consent")        ; Force consent screen to get refresh token
      (state . ,state)))
  
  (format "https://accounts.google.com/o/oauth2/v2/auth?~a"
          (alist->form-urlencoded params)))

;; Custom Gmail OAuth flow that requests refresh tokens
;; We manually build the auth URL to include access_type=offline,
;; but use simple-oauth2's infrastructure for everything else
(define (authorize-gmail)
  (displayln "Starting Gmail OAuth authorization flow...")
  (displayln "Building custom auth URL to request refresh tokens...")
  
  (define-values (client-id client-secret redirect-uri) (load-credentials-from-file))
  (define gmail-client (make-gmail-client))
  (define user-name (get-current-user-name))
  (define state (create-random-state))
  
  ;; Build custom auth URL with access_type=offline
  (define auth-url (make-gmail-auth-url client-id gmail-scopes state))
  
  (displayln "\nPlease open this URL in your browser:")
  (displayln auth-url)
  (displayln "")
  
  ;; Use simple-oauth2's redirect server infrastructure
  (define response-channel (record-auth-request state))
  
  ;; Give the server a moment to start accepting connections
  (displayln "Starting OAuth redirect server...")
  (sleep 1)
  
  ;; Open browser
  (displayln "Opening browser...")
  (system (format "xdg-open '~a' 2>/dev/null || open '~a' 2>/dev/null || start '~a' 2>NUL" 
                  auth-url auth-url auth-url))
  
  ;; Wait for callback
  (displayln "Waiting for authorization callback...")
  (define auth-code (channel-get response-channel))
  
  (when (exn:fail? auth-code)
    (raise auth-code))
  
  (displayln (format "Got authorization code: ~a..." (substring auth-code 0 20)))
  
  ;; Exchange code for tokens
  (displayln "Exchanging code for tokens...")
  (define token (grant-token/from-authorization-code gmail-client auth-code))
  
  (displayln "\n=== Authorization complete! ===")
  (define access-str (if (bytes? (token-access-token token))
                         (bytes->string/utf-8 (token-access-token token))
                         (token-access-token token)))
  (displayln (format "Access token: ~a..." (substring access-str 0 20)))
  
  (if (token-refresh-token token)
      (let ([refresh-str (if (bytes? (token-refresh-token token))
                             (bytes->string/utf-8 (token-refresh-token token))
                             (token-refresh-token token))])
        (displayln (format "✓ Refresh token: ~a..." (substring refresh-str 0 20))))
      (displayln "✗ WARNING: No refresh token received!"))
  
  ;; Store for later use
  (set-token! user-name "gmail" token)
  (save-tokens)  ; Persist to disk!
  (displayln "\n✓ Tokens stored successfully!")
  token)

;; Check if token is expired
(define (token-expired? token)
  (> (current-seconds) (token-expires token)))

;; Force token refresh (ignoring timestamp check)
;; Used when we get a 401 error, indicating the token is invalid
;; even if the timestamp says it shouldn't be expired yet
(define (force-token-refresh stored-token user-name)
  (displayln "  → Forcing token refresh due to authentication error...")
  (define refreshed (refresh-token (make-gmail-client) stored-token))
  ;; Google doesn't return refresh_token in refresh response, so preserve the old one
  (define refreshed-with-refresh-token
    (if (token-refresh-token refreshed)
        refreshed  ; New token has refresh token (unlikely but handle it)
        (struct-copy token refreshed
                     [refresh-token (token-refresh-token stored-token)])))
  (set-token! user-name "gmail" refreshed-with-refresh-token)
  (save-tokens)  ; Persist refreshed token
  (displayln "  ✓ Token refreshed successfully")
  refreshed-with-refresh-token)

;; Get current access token (refresh if needed)
(define (get-gmail-token #:force-refresh? [force-refresh? #f])
  (let ([user-name (get-current-user-name)])
    (define stored-token
      (with-handlers ([exn:fail? (λ (e)
                                   (displayln "⚠ Token decryption failed (corrupted token file)")
                                   (displayln (format "  Error: ~a" (exn-message e)))
                                   (displayln "  Automatically re-authorizing...")
                                   #f)])
        (get-token user-name "gmail")))
    
    (if stored-token
        ;; Check if expired or force refresh requested
        (if (or force-refresh? (token-expired? stored-token))
            (with-handlers ([exn:fail? (λ (e)
                                         (displayln "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                                         (displayln "⚠ TOKEN REFRESH FAILED")
                                         (displayln (format "  Error: ~a" (exn-message e)))
                                         (displayln "  ")
                                         (displayln "  Your access token expired and automatic refresh failed.")
                                         (displayln "  This usually happens after ~1 hour of running.")
                                         (displayln "  ")
                                         (displayln "  You need to re-authorize in your browser.")
                                         (displayln "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
                                         (displayln "Press Enter to open browser for re-authorization...")
                                         (read-line)
                                         (authorize-gmail))])
              (unless force-refresh?
                (displayln "Access token expired, refreshing..."))
              (force-token-refresh stored-token user-name))
            stored-token)
        (begin
          (displayln "No stored token found. Authorizing...")
          (authorize-gmail)))))

;; Check if an exception is a transient network error that should be retried
(define (transient-network-error? exn)
  (define msg (exn-message exn))
  (or (regexp-match? #rx"timed out" msg)           ; Catches "connect timed out", "Connection timed out", "request timed out", etc.
      (regexp-match? #rx"[Cc]onnection reset" msg)
      (regexp-match? #rx"[Cc]onnection refused" msg)
      (regexp-match? #rx"Network is unreachable" msg)
      (regexp-match? #rx"error reading from stream" msg)))

;; Check if an exception is a 401 authentication error
(define (auth-error? exn)
  (define msg (exn-message exn))
  (regexp-match? #rx"Gmail API error 401" msg))

;; Make authenticated Gmail API request with retry logic
(define (gmail-api-request endpoint 
                          #:method [method "GET"] 
                          #:data [data #f]
                          #:max-retries [max-retries 3]
                          #:base-delay [base-delay 1])
  (define url (string-append "https://gmail.googleapis.com/gmail/v1/users/me/" endpoint))
  
  ;; Convert data to bytes if needed
  (define data-bytes (if (and data (string? data))
                         (string->bytes/utf-8 data)
                         data))
  
  ;; Add Content-Type header for POST/PUT with data
  (define extra-headers 
    (if data-bytes
        (list #"Content-Type: application/json")
        '()))
  
  ;; Track whether we've tried force-refreshing the token
  (define tried-force-refresh? #f)
  
  ;; Retry loop with exponential backoff
  (define (attempt retry-count)
    ;; Fetch token fresh on each attempt (critical for expired tokens during retries)
    (define token (get-gmail-token #:force-refresh? (and tried-force-refresh? (zero? retry-count))))
    
    (with-handlers ([exn:fail? 
                     (λ (exn)
                       (cond
                         ;; Handle 401 auth errors - try forcing token refresh once
                         [(and (auth-error? exn) (not tried-force-refresh?))
                          (displayln "  ⚠ Authentication error (401) - token may be stale")
                          (set! tried-force-refresh? #t)
                          (attempt 0)]  ; Reset retry count for auth retry
                         
                         ;; Handle transient network errors with exponential backoff
                         [(and (transient-network-error? exn)
                               (< retry-count max-retries))
                          (let ([delay (* base-delay (expt 2 retry-count))])
                            (displayln (format "  ⚠ Network error: ~a" (exn-message exn)))
                            (displayln (format "  → Retrying in ~a seconds (attempt ~a/~a)..." 
                                              delay 
                                              (+ retry-count 1)
                                              max-retries))
                            (sleep delay)
                            (attempt (+ retry-count 1)))]
                         
                         ;; No more retries, propagate the error
                         [else (raise exn)]))])
      ;; Wrap API call with timeout (60 seconds)
      (define result-ch (make-async-channel))
      (define worker-thread
        (thread
         (λ ()
           (with-handlers ([exn:fail? (λ (e) (async-channel-put result-ch e))])
             (define result (resource-sendrecv url token 
                                              #:method method 
                                              #:data data-bytes
                                              #:headers extra-headers))
             (async-channel-put result-ch result)))))
      
      (define result
        (sync/timeout 60  ; 60 second timeout
                      (handle-evt result-ch (λ (x) x))))
      
      ;; Check if timeout occurred
      (unless result
        (kill-thread worker-thread)
        (error "Gmail API request timed out after 60 seconds"))
      
      ;; If result is an exception, raise it
      (when (exn:fail? result)
        (raise result))
      
      ;; result is (list http-code http-message headers body)
      (match result
        [(list code message headers body)
         (if (and (>= code 200) (< code 300))
             (with-input-from-string (bytes->string/utf-8 body) read-json)
             (error (format "Gmail API error ~a: ~a" code (bytes->string/utf-8 body))))])))
  
  (attempt 0))

;; Module exports
(provide authorize-gmail
         get-gmail-token
         gmail-api-request)
