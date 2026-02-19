#lang racket

;; Gmail send API

(require "oauth.rkt"
         "gmail.rkt"
         json
         net/base64
         net/uri-codec
         racket/system
         racket/runtime-path)

;; Resolve paths relative to this source file at compile time
(define-runtime-path src-dir ".")
(define email-css-path (path->string (build-path src-dir ".." "config" "email.css")))

;; Tool paths
(define pandoc-bin     "/home/danenberg/bin/pandoc")
(define css-inline-bin "/home/danenberg/.cargo/bin/css-inline")

;; Run a shell command and return stdout as a string
;; Raises an error if the command exits non-zero
(define (shell-capture cmd)
  (define out (open-output-string))
  (define exit-code
    (parameterize ([current-output-port out])
      (system/exit-code cmd)))
  (unless (zero? exit-code)
    (error (format "Command failed (exit ~a): ~a" exit-code cmd)))
  (get-output-string out))

;; Convert Markdown body to plain text via pandoc
(define (markdown->plain markdown)
  (define tmpfile "/tmp/schemail-body.md")
  (with-output-to-file tmpfile #:exists 'replace
    (λ () (display markdown)))
  (shell-capture (format "~a -f markdown -t plain ~a" pandoc-bin tmpfile)))

;; Convert Markdown body to HTML via pandoc + css-inline
;; Pipeline: pandoc --standalone (embeds CSS in <style>) | css-inline (inlines to style= attrs)
(define (markdown->html markdown)
  (define tmpfile "/tmp/schemail-body.md")
  (with-output-to-file tmpfile #:exists 'replace
    (λ () (display markdown)))
  (shell-capture
   (format "~a --standalone --embed-resources --css ~a -f markdown -t html ~a | ~a"
           pandoc-bin email-css-path tmpfile css-inline-bin)))

;; Build multipart/alternative RFC 2822 message via mime-construct
;; Falls back to plain text if conversion fails
(define (build-email-message #:from from
                             #:to to
                             #:subject subject
                             #:body body
                             #:cc [cc #f]
                             #:in-reply-to [in-reply-to #f]
                             #:references [references #f])
  (define plain-tmp "/tmp/schemail-plain.txt")
  (define html-tmp  "/tmp/schemail-html.html")

  ;; Try markdown conversion; fall back to plain text on error
  (define-values (plain html)
    (with-handlers ([exn:fail?
                     (λ (e)
                       (displayln (format "⚠ Markdown conversion failed: ~a" (exn-message e)))
                       (displayln "  → Falling back to plain text")
                       (values body #f))])
      (values (markdown->plain body)
              (markdown->html body))))

  (cond
    ;; Full multipart/alternative via mime-construct
    [html
     (with-output-to-file plain-tmp #:exists 'replace (λ () (display plain)))
     (with-output-to-file html-tmp  #:exists 'replace (λ () (display html)))
     ;; Build extra headers as --header args
     (define extra-headers
       (string-append
        (if in-reply-to (format "--header 'In-Reply-To: ~a' " in-reply-to) "")
        (if references  (format "--header 'References: ~a' "  references)  "")
        (if cc          (format "--header 'Cc: ~a' "          cc)          "")))
     (shell-capture
      (format "mime-construct --output ~a --header 'From: ~a' --header 'To: ~a' --header 'Subject: ~a' --multipart multipart/alternative --type text/plain --file ~a --type text/html --file ~a"
              extra-headers from to subject plain-tmp html-tmp))]

    ;; Plain text fallback
    [else
     (string-append
      (format "From: ~a\r\n" from)
      (format "To: ~a\r\n" to)
      (if cc          (format "Cc: ~a\r\n"          cc)          "")
      (format "Subject: ~a\r\n" subject)
      (if in-reply-to (format "In-Reply-To: ~a\r\n" in-reply-to) "")
      (if references  (format "References: ~a\r\n"  references)  "")
      "Content-Type: text/plain; charset=utf-8\r\n"
      "\r\n"
      body)]))

;; Base64url encode (Gmail API requirement)
(define (base64url-encode str-or-bytes)
  (define bstr (if (bytes? str-or-bytes)
                   str-or-bytes
                   (string->bytes/utf-8 str-or-bytes)))
  (define b64 (base64-encode bstr #""))
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
