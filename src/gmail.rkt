#lang racket

;; Gmail API wrapper functions

(require "oauth.rkt"
         json
         net/uri-codec)

;; ============================================================================
;; Messages
;; ============================================================================

;; List messages (with optional query)
(define (gmail-list-messages #:query [query #f] #:max-results [max-results 100])
  (define endpoint (if query
                       (format "messages?q=~a&maxResults=~a" 
                               (uri-encode query)
                               max-results)
                       (format "messages?maxResults=~a" max-results)))
  (gmail-api-request endpoint))

;; Get a single message by ID
(define (gmail-get-message message-id #:format [msg-format "full"])
  (gmail-api-request (format "messages/~a?format=~a" message-id msg-format)))

;; Modify message labels
(define (gmail-modify-message message-id 
                              #:add-labels [add-labels '()]
                              #:remove-labels [remove-labels '()])
  (define data (hasheq 'addLabelIds add-labels
                       'removeLabelIds remove-labels))
  (gmail-api-request (format "messages/~a/modify" message-id)
                     #:method "POST"
                     #:data (jsexpr->string data)))

;; Batch modify messages
(define (gmail-batch-modify message-ids
                            #:add-labels [add-labels '()]
                            #:remove-labels [remove-labels '()])
  (define data (hasheq 'ids message-ids
                       'addLabelIds add-labels
                       'removeLabelIds remove-labels))
  (gmail-api-request "messages/batchModify"
                     #:method "POST"
                     #:data (jsexpr->string data)))

;; ============================================================================
;; Labels
;; ============================================================================

;; List all labels
(define (gmail-list-labels)
  (gmail-api-request "labels"))

;; Get label by ID
(define (gmail-get-label label-id)
  (gmail-api-request (format "labels/~a" label-id)))

;; Create a new label
(define (gmail-create-label name #:color [color #f])
  (define data (if color
                   (hasheq 'name name
                           'color color)
                   (hasheq 'name name)))
  (gmail-api-request "labels"
                     #:method "POST"
                     #:data (jsexpr->string data)))

;; Find label ID by name
(define (gmail-find-label-by-name name)
  (define labels-response (gmail-list-labels))
  (define labels (hash-ref labels-response 'labels '()))
  (for/first ([label labels]
              #:when (string=? (hash-ref label 'name) name))
    (hash-ref label 'id)))

;; Update label properties (e.g., visibility)
(define (gmail-update-label label-id
                            #:label-list-visibility [label-list-visibility #f]
                            #:message-list-visibility [message-list-visibility #f]
                            #:name [name #f]
                            #:background-color [background-color #f]
                            #:text-color [text-color #f])
  (define data (make-hash))
  (when label-list-visibility (hash-set! data 'labelListVisibility label-list-visibility))
  (when message-list-visibility (hash-set! data 'messageListVisibility message-list-visibility))
  (when name (hash-set! data 'name name))
  (when (or background-color text-color)
    (define color-data (make-hash))
    (when background-color (hash-set! color-data 'backgroundColor background-color))
    (when text-color (hash-set! color-data 'textColor text-color))
    (hash-set! data 'color color-data))
  (gmail-api-request (format "labels/~a" label-id)
                     #:method "PATCH"
                     #:data (jsexpr->string data)))

;; Delete a label
(define (gmail-delete-label label-id)
  (gmail-api-request (format "labels/~a" label-id)
                     #:method "DELETE"))

;; ============================================================================
;; Helpers
;; ============================================================================

;; Extract headers from message
(define (message-header message header-name)
  (define payload (hash-ref message 'payload #f))
  (when payload
    (define headers (hash-ref payload 'headers '()))
    (for/first ([header headers]
                #:when (string-ci=? (hash-ref header 'name) header-name))
      (hash-ref header 'value))))

;; Get message subject
(define (message-subject message)
  (message-header message "Subject"))

;; Get message from
(define (message-from message)
  (message-header message "From"))

;; Get message date
(define (message-date message)
  (message-header message "Date"))

;; Get message snippet (preview text)
(define (message-snippet message)
  (hash-ref message 'snippet ""))

;; Check if message has label
(define (message-has-label? message label-id)
  (define label-ids (hash-ref message 'labelIds '()))
  (member label-id label-ids))

;; Module exports
(provide gmail-list-messages
         gmail-get-message
         gmail-modify-message
         gmail-batch-modify
         gmail-list-labels
         gmail-get-label
         gmail-create-label
         gmail-update-label
         gmail-delete-label
         gmail-find-label-by-name
         message-subject
         message-from
         message-date
         message-snippet
         message-header
         message-has-label?)
