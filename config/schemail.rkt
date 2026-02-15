#lang racket

;; Schemail configuration

(provide (all-defined-out))

;; ============================================================================
;; Classifier Configuration
;; ============================================================================

;; Default classifier experiment to use
;; Options: 'experiment-1 (blank slate + label context)
;;          'experiment-2 (inbox zero principles + label context)
;;          'experiment-3 (explicit inbox zero framework + label context) [RECOMMENDED]
;; 
;; Experiment 3 is the production choice after 50-email testing:
;;   - 45% fewer labels than Experiment 1 (6 vs 11)
;;   - Better inbox discrimination (only human-action emails kept)
;;   - Action-oriented categories (Action Required/Response)
;;   - Framework thinking prevents label proliferation
(define default-classifier 'experiment-3)

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
    [(default-classifier) default-classifier]
    [(color-scheme) color-scheme]
    [(exclude-from-coloring) exclude-from-coloring]
    [else #f]))
