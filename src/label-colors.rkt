#lang racket

;; Label color assignment - applies colors to Gmail labels

(require "gmail.rkt"
         "colors.rkt"
         "../config/schemail.rkt")

(provide apply-label-colors!
         cleanup-experiment-labels!)

;; ============================================================================
;; Label Color Application
;; ============================================================================

;; Apply colors to all user labels
(define (apply-label-colors! #:scheme [scheme (get-config 'color-scheme)])
  (unless scheme
    (displayln "No color scheme configured. Skipping label coloring.")
    (void))
  
  (when scheme
    (displayln (format "\n=== Applying '~a' color scheme ===" scheme))
    
    ;; Get all labels
    (define all-labels (gmail-list-labels))
    (define label-list (hash-ref all-labels 'labels '()))
    
    ;; Filter to user labels (exclude system and Schemail marker)
    (define user-labels
      (filter (λ (label)
                (define name (hash-ref label 'name))
                (define type (hash-ref label 'type))
                (and (equal? type "user")
                     (not (equal? name "Schemail"))
                     (not (member name (get-config 'exclude-from-coloring)))))
              label-list))
    
    (when (empty? user-labels)
      (displayln "No user labels found to color.")
      (void))
    
    (unless (empty? user-labels)
      ;; Fetch full details for each label to get message counts
      (displayln "Fetching label details...")
      (define labels-with-counts
        (for/list ([label user-labels])
          (define label-id (hash-ref label 'id))
          (gmail-get-label label-id)))
      
      ;; Filter to labels with messages (messagesTotal > 0)
      (define labels-with-messages
        (filter (λ (label)
                  (define total (hash-ref label 'messagesTotal 0))
                  (> total 0))
                labels-with-counts))
      
      (define initial-count (length user-labels))
      (define filtered-count (length labels-with-messages))
      (define skipped-count (- initial-count filtered-count))
      
      (displayln (format "Found ~a user label(s), ~a with messages (~a empty, skipped)"
                        initial-count filtered-count skipped-count))
      
      (when (> skipped-count 0)
        (displayln "\nSkipped empty labels:")
        (for ([label labels-with-counts]
              #:when (= (hash-ref label 'messagesTotal 0) 0))
          (displayln (format "  - ~a (0 messages)" (hash-ref label 'name)))))
      
      (when (empty? labels-with-messages)
        (displayln "\nNo labels with messages to color.")
        (void))
      
      (unless (empty? labels-with-messages)
        ;; Generate colors for labels with messages
        (define colors (generate-label-colors scheme filtered-count))
        
        ;; Apply colors
        (displayln "")
        (for ([label labels-with-messages] [color colors] [i (in-naturals 1)])
          (define label-id (hash-ref label 'id))
          (define label-name (hash-ref label 'name))
          (define message-count (hash-ref label 'messagesTotal))
          (define text-color (text-color-for-background color))
          (displayln (format "  [~a/~a] ~a (~a msgs) → bg:~a text:~a" 
                            i filtered-count label-name message-count color text-color))
          (gmail-update-label label-id #:background-color color #:text-color text-color))
        
        (displayln (format "\n✓ Applied colors to ~a label(s)!" filtered-count))))))

;; ============================================================================
;; Label Cleanup
;; ============================================================================

;; Delete all user labels except those in exclude-from-coloring
;; Also deletes the Schemail marker to allow reprocessing emails
(define (cleanup-experiment-labels!)
  (displayln "\n=== Cleaning up experiment labels ===")
  
  ;; Get all labels
  (define all-labels (gmail-list-labels))
  (define label-list (hash-ref all-labels 'labels '()))
  
  ;; Get exclusion list from config
  (define excluded-labels (get-config 'exclude-from-coloring))
  
  ;; Filter to user labels that should be deleted (including Schemail)
  (define labels-to-delete
    (filter (λ (label)
              (define name (hash-ref label 'name))
              (define type (hash-ref label 'type))
              (and (equal? type "user")
                   (not (member name excluded-labels))))  ; Keep only excluded labels
            label-list))
  
  (when (empty? labels-to-delete)
    (displayln "No labels to delete.")
    (void))
  
  (unless (empty? labels-to-delete)
    (define count (length labels-to-delete))
    (displayln (format "Found ~a label(s) to delete:" count))
    (for ([label labels-to-delete])
      (displayln (format "  - ~a" (hash-ref label 'name))))
    
    (displayln "\n⚠ Warning: This will permanently delete these labels!")
    (displayln "  (Including Schemail marker - emails will be reprocessable)")
    (display "Type 'yes' to confirm: ")
    (flush-output)
    (define response (read-line))
    
    (if (equal? response "yes")
        (begin
          (displayln "")
          (for ([label labels-to-delete] [i (in-naturals 1)])
            (define label-id (hash-ref label 'id))
            (define label-name (hash-ref label 'name))
            (displayln (format "  [~a/~a] Deleting ~a..." i count label-name))
            (gmail-delete-label label-id))
          (displayln (format "\n✓ Deleted ~a label(s)!" count))
          (displayln "✓ Emails are now unprocessed and can be run through experiments again"))
        (displayln "\nCancelled. No labels were deleted."))))
