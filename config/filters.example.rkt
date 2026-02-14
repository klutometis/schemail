#lang racket

;; Example email filters
;; Copy this to filters.rkt and customize

(provide filters)

(define filters
  '(
    ;; Archive receipts
    (filter (or (subject "receipt")
                (subject "invoice")
                (from "noreply@"))
            (label "Receipt")
            (archive)
            (mark-read))
    
    ;; Newsletter handling
    (filter (or (subject "newsletter")
                (subject "digest")
                (from "substack.com"))
            (label "Newsletter")
            (mark-read))
    
    ;; Mark important people
    (filter (or (from "boss@company.com")
                (from "client@important.com"))
            (label "Important")
            (star))
    
    ;; GitHub notifications
    (filter (from "notifications@github.com")
            (label "GitHub")
            (archive))
    
    ;; Catch-all: anything from known mailing lists
    (filter (body "unsubscribe")
            (label "Mailing List")
            (archive))
    ))
