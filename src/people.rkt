#lang racket

;; Google People API - Get user profile information

(require "oauth.rkt"
         oauth2
         oauth2/client
         json
         net/http-client
         net/uri-codec)

;; Make authenticated People API request
(define (people-api-request endpoint)
  (define token (get-gmail-token))
  (define url (string-append "https://people.googleapis.com/v1/" endpoint))
  
  (define result (resource-sendrecv url token #:method "GET"))
  
  ;; result is (list http-code http-message headers body)
  (match result
    [(list code message headers body)
     (if (and (>= code 200) (< code 300))
         (with-input-from-string (bytes->string/utf-8 body) read-json)
         (error (format "People API error ~a: ~a" code (bytes->string/utf-8 body))))]))

;; Get user profile from People API
(define (people-get-profile)
  (people-api-request "people/me?personFields=names,emailAddresses"))

;; Extract display name from profile
(define (people-get-display-name)
  (with-handlers ([exn:fail? (λ (e)
                               (displayln (format "⚠ Could not fetch display name: ~a" (exn-message e)))
                               #f)])
    (define profile (people-get-profile))
    (define names (hash-ref profile 'names '()))
    (if (empty? names)
        #f  ; No name available
        (hash-ref (first names) 'displayName #f))))

;; Extract given name (first name)
(define (people-get-given-name)
  (with-handlers ([exn:fail? (λ (e)
                               (displayln (format "⚠ Could not fetch given name: ~a" (exn-message e)))
                               #f)])
    (define profile (people-get-profile))
    (define names (hash-ref profile 'names '()))
    (if (empty? names)
        #f
        (hash-ref (first names) 'givenName #f))))

;; Format email address with display name
;; "Peter Danenberg <peter@danenberg.ai>"
(define (format-email-with-name email [name #f])
  (if (and name (not (string=? name "")))
      (format "~a <~a>" name email)
      email))

(provide people-get-profile
         people-get-display-name
         people-get-given-name
         format-email-with-name)
