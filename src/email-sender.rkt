#lang racket

;; Gmail send API

(require "oauth.rkt"
         "gmail.rkt"
         json
         net/base64
         net/uri-codec)

;; Build RFC 2822 email message
(define (build-email-message #:from from
                             #:to to
                             #:subject subject
                             #:body body
                             #:cc [cc #f]
                             #:in-reply-to [in-reply-to #f]
                             #:references [references #f])
  (define headers
    (string-append
     (format "From: ~a\r\n" from)
     (format "To: ~a\r\n" to)
     (if cc (format "Cc: ~a\r\n" cc) "")
     (format "Subject: ~a\r\n" subject)
     (if in-reply-to
         (format "In-Reply-To: ~a\r\n" in-reply-to)
         "")
     (if references
         (format "References: ~a\r\n" references)
         "")
     "Content-Type: text/plain; charset=utf-8\r\n"
     "\r\n"))
  
  (string-append headers body))

;; Base64url encode (Gmail API requirement)
(define (base64url-encode str)
  (define b64 (base64-encode (string->bytes/utf-8 str) #""))
  (define b64-str (bytes->string/utf-8 b64))
  ;; Replace + with -, / with _, remove padding =
  (string-replace
   (string-replace
    (string-replace b64-str "+" "-")
    "/" "_")
   "=" ""))

;; Send email via Gmail API
(define (gmail-send-email #:from from
                          #:to to
                          #:subject subject
                          #:body body
                          #:cc [cc #f]
                          #:thread-id [thread-id #f]
                          #:in-reply-to [in-reply-to #f]
                          #:references [references #f])
  (define message-str
    (build-email-message #:from from
                        #:to to
                        #:subject subject
                        #:body body
                        #:cc cc
                        #:in-reply-to in-reply-to
                        #:references references))
  
  (define encoded (base64url-encode message-str))
  
  (define data
    (if thread-id
        (hasheq 'raw encoded 'threadId thread-id)
        (hasheq 'raw encoded)))
  
  (gmail-api-request "messages/send"
                     #:method "POST"
                     #:data (jsexpr->string data)))

;; Get user's email address
(define (gmail-get-user-email)
  (define profile (gmail-api-request "profile"))
  (hash-ref profile 'emailAddress))

(provide gmail-send-email
         gmail-get-user-email)
