#lang racket

;; Shared utilities for Gmail label operations
;; Used by both llm.rkt and llm-classifier.rkt

(require "gmail.rkt")

(provide normalize-label
         ensure-schemail-marker
         ensure-label-hierarchy
         apply-content-and-marker-labels
         archive-message)

;; ============================================================================
;; Label Normalization
;; ============================================================================

;; Normalize a single label part: titlecase + replace non-alphanumeric with spaces
(define (normalize-label-part part)
  (string-titlecase 
   (string-trim (regexp-replace* #rx"[^a-zA-Z0-9]+" part " "))))

;; Normalize a label name (handles hierarchical labels with /)
;; Examples:
;;   "verification-code" -> "Verification Code"
;;   "Newsletter/Marketing" -> "Newsletter/Marketing"
;;   "news_letter/order-confirmation" -> "News Letter/Order Confirmation"
(define (normalize-label raw-label)
  (if (string-contains? raw-label "/")
      (string-join (map normalize-label-part (string-split raw-label "/")) "/")
      (normalize-label-part raw-label)))

;; ============================================================================
;; Schemail Marker Management
;; ============================================================================

;; Ensure the "Schemail" marker label exists and is properly hidden.
;; Returns the label ID.
;; The marker is hidden from both sidebar (labelListVisibility: labelHide)
;; and message list (messageListVisibility: hide).
(define (ensure-schemail-marker)
  (define marker-id (gmail-find-label-by-name "Schemail"))
  (if marker-id
      marker-id
      (let* ([marker-label (begin
                             (displayln "  → Creating Schemail marker label")
                             (gmail-create-label "Schemail"))]
             [new-id (hash-ref marker-label 'id)])
        (displayln "  → Hiding Schemail from sidebar and message list")
        (gmail-update-label new-id 
                           #:label-list-visibility "labelHide"
                           #:message-list-visibility "hide")
        new-id)))

;; ============================================================================
;; Hierarchical Label Handling
;; ============================================================================

;; Ensure parent labels exist for hierarchical labels (e.g., "Newsletter/Marketing")
;; Gmail requires parent labels to exist before creating child labels.
(define (ensure-label-hierarchy label-name)
  (when (string-contains? label-name "/")
    (define parent-name (car (string-split label-name "/")))
    (define parent-id (gmail-find-label-by-name parent-name))
    (unless parent-id
      (displayln (format "  → Creating parent label: ~a" parent-name))
      (gmail-create-label parent-name))))

;; ============================================================================
;; Label Application
;; ============================================================================

;; Apply both content label and Schemail marker to a message.
;; Creates labels if they don't exist.
;; Returns the content label ID (for reference).
(define (apply-content-and-marker-labels message-id content-label marker-id)
  ;; Ensure hierarchy exists
  (ensure-label-hierarchy content-label)
  
  ;; Find or create content label
  (define content-label-id 
    (or (gmail-find-label-by-name content-label)
        (let ([new-label (begin
                           (displayln (format "  → Creating label: ~a" content-label))
                           (gmail-create-label content-label))])
          (hash-ref new-label 'id))))
  
  ;; Apply both labels
  (displayln (format "  → Applying labels: ~a + Schemail (marker)" content-label))
  (gmail-modify-message message-id #:add-labels (list content-label-id marker-id))
  (displayln "  ✓ Labels applied")
  
  content-label-id)

;; ============================================================================
;; Archive Operation
;; ============================================================================

;; Archive a message (remove from INBOX)
(define (archive-message message-id)
  (displayln "  → Archiving (removing from INBOX)")
  (gmail-modify-message message-id #:remove-labels '("INBOX"))
  (displayln "  ✓ Archived"))
