#lang racket

;; Schemail configuration

(provide (all-defined-out))

;; ============================================================================
;; Label Color Configuration
;; ============================================================================

;; Color scheme for labels
;; Options: 'set1, 'set2, 'set3, 'paired, 'dark2, 'pastel1, 'pastel2,
;;          'accent, 'bright, 'high-contrast, 'vibrant, 'muted, 
;;          'pale, 'dark, 'light, 'rainbow, or #f to disable
;; 
;; Note: If you have more labels than colors in the scheme, colors will cycle.
;;       Use 'rainbow for unlimited distinct colors (dynamically generated).
(define color-scheme 'rainbow)

;; Labels to exclude from coloring (optional)
;; Example: '("ImportantProject" "PersonalStuff")
(define exclude-from-coloring '("Groups" "Saved"))

;; ============================================================================
;; Helper Functions
;; ============================================================================

;; Get configuration value
(define (get-config key)
  (case key
    [(color-scheme) color-scheme]
    [(exclude-from-coloring) exclude-from-coloring]
    [else #f]))
