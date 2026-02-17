#lang racket

;; AI-powered email reply drafting

(require "llm-classifier.rkt"
         "gmail.rkt"
         json
         net/http-easy
         net/base64)

;; Draft a reply using Claude
(define (draft-reply message 
                     #:user-email [user-email ""]
                     #:thread-context [thread-context ""])
  (define from (message-from message))
  (define to (message-header message "To"))
  (define subject (message-subject message))
  (define body (get-email-body message))
  
  (define prompt
    (format "You are an email reply assistant. Draft a professional, concise email reply.

YOU ARE: ~a

ORIGINAL EMAIL:
From: ~a
To: ~a
Subject: ~a

~a

~a

INSTRUCTIONS:
1. Draft a clear, professional reply
2. Match the tone of the original (formal/casual)
3. Be concise (2-4 sentences usually)
4. Address all questions/requests
5. Output ONLY the reply body, no subject line

Reply:"
            user-email
            from
            to
            subject
            body
            (if (string=? thread-context "")
                ""
                (format "\nPREVIOUS THREAD CONTEXT:\n~a\n" thread-context))))
  
  ;; Call Claude API
  (define api-key (getenv "ANTHROPIC_API_KEY"))
  (unless api-key
    (error "ANTHROPIC_API_KEY environment variable not set"))
  
  (define response
    (post "https://api.anthropic.com/v1/messages"
          #:headers (hash 'x-api-key api-key
                         'anthropic-version "2023-06-01"
                         'content-type "application/json")
          #:data (jsexpr->string
                  (hasheq 'model (current-model)
                          'max_tokens 1024
                          'messages (list
                                     (hasheq 'role "user"
                                            'content prompt))))))
  
  (define json-response (response-json response))
  (define content (hash-ref json-response 'content))
  (define text (hash-ref (first content) 'text))
  
  text)

;; Get email body (try to get plain text)
(define (get-email-body message)
  (define payload (hash-ref message 'payload #f))
  (when (not payload)
    (error "No payload in message"))
  
  ;; Try to get body
  (define body (hash-ref payload 'body))
  (define body-data (hash-ref body 'data #f))
  
  (if body-data
      ;; Decode base64url
      (decode-base64url body-data)
      ;; Try parts
      (extract-text-from-parts (hash-ref payload 'parts '()))))

;; Extract text from parts (handles nested multipart)
(define (extract-text-from-parts parts)
  (if (empty? parts)
      "[No body content]"
      ;; Try text/plain first
      (let ([text-part (findf (λ (p) (equal? (hash-ref p 'mimeType "") "text/plain")) parts)])
        (if text-part
            (get-part-body text-part)
            ;; Try text/html
            (let ([html-part (findf (λ (p) (equal? (hash-ref p 'mimeType "") "text/html")) parts)])
              (if html-part
                  (string-append "[HTML email]\n\n" (get-part-body html-part))
                  ;; Check for nested multipart (e.g., multipart/alternative)
                  (let ([multipart (findf (λ (p) 
                                            (string-prefix? (hash-ref p 'mimeType "") "multipart/"))
                                         parts)])
                    (if multipart
                        ;; Recurse into nested parts
                        (extract-text-from-parts (hash-ref multipart 'parts '()))
                        "[No readable content - may have attachments only]"))))))))

;; Get body from a part
(define (get-part-body part)
  (define body (hash-ref part 'body))
  (define body-data (hash-ref body 'data #f))
  (if body-data
      (decode-base64url body-data)
      "[No body data]"))

;; Decode base64url (Gmail format)
(define (decode-base64url str)
  (define normalized
    ;; Replace - with +, _ with /
    (string-replace (string-replace str "-" "+") "_" "/"))
  ;; Add padding if needed
  (define padded
    (let ([len (string-length normalized)])
      (define pad-len (modulo (- 4 (modulo len 4)) 4))
      (string-append normalized (make-string pad-len #\=))))
  
  (bytes->string/utf-8 (base64-decode (string->bytes/utf-8 padded))))

(provide draft-reply
         get-email-body)
