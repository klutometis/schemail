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
         net/uri-codec)

;; Gmail API scopes
(define gmail-scopes
  (list "https://www.googleapis.com/auth/gmail.readonly"
        "https://www.googleapis.com/auth/gmail.modify"
        "https://www.googleapis.com/auth/gmail.labels"))

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

;; Get current access token (refresh if needed)
(define (get-gmail-token)
  (let ([user-name (get-current-user-name)]
        [stored-token (get-token (get-current-user-name) "gmail")])
    (if stored-token
        ;; Check if expired and refresh if needed
        (if (token-expired? stored-token)
            (let ([refreshed (refresh-token (make-gmail-client) stored-token)])
              (displayln "Access token expired, refreshing...")
              (set-token! user-name "gmail" refreshed)
              (save-tokens)  ; Persist refreshed token
              refreshed)
            stored-token)
        (begin
          (displayln "No stored token found. Please authorize first.")
          (authorize-gmail)))))

;; Make authenticated Gmail API request
(define (gmail-api-request endpoint #:method [method "GET"] #:data [data #f])
  (define token (get-gmail-token))
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
  
  (define result (resource-sendrecv url token 
                                    #:method method 
                                    #:data data-bytes
                                    #:headers extra-headers))
  
  ;; result is (list http-code http-message headers body)
  (match result
    [(list code message headers body)
     (if (and (>= code 200) (< code 300))
         (with-input-from-string (bytes->string/utf-8 body) read-json)
         (error (format "Gmail API error ~a: ~a" code (bytes->string/utf-8 body))))]))

;; Module exports
(provide authorize-gmail
         get-gmail-token
         gmail-api-request)
