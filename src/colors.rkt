#lang racket

;; Color utilities for label coloring

(require colormaps/tol
         colormaps/cb
         plot
         plot/utils
         racket/match)

(provide generate-label-colors
         rgb->gmail-color
         text-color-for-background
         scheme-info)

;; ============================================================================
;; Gmail Color Palette (101 fixed colors)
;; ============================================================================

(define GMAIL-PALETTE
  '("#000000" "#04502e" "#076239" "#094228" "#0b4f30" "#0b804b" "#0d3472" "#0d3b44"
    "#149e60" "#16a765" "#16a766" "#1a764d" "#1c4587" "#285bac" "#2a9c68" "#2da2bb"
    "#3c78d8" "#3d188e" "#3dc789" "#41236d" "#42d692" "#434343" "#43d692" "#44b984"
    "#464646" "#4986e7" "#4a86e8" "#594c05" "#653e9b" "#662e37" "#666666" "#684e07"
    "#68dfa9" "#6d9eeb" "#711a36" "#7a2e0b" "#7a4706" "#822111" "#83334c" "#89d3b2"
    "#8a1c0a" "#8e63ce" "#98d7e4" "#994a64" "#999999" "#a0eac9" "#a2dcc1" "#a46a21"
    "#a479e2" "#a4c2f4" "#aa8831" "#ac2b16" "#b3efd3" "#b65775" "#b694e8" "#b6cff5"
    "#b99aff" "#b9e4d0" "#c2c2c2" "#c6f3de" "#c9daf8" "#cc3a21" "#cca6ac" "#cccccc"
    "#cf8933" "#d0bcf1" "#d5ae49" "#e07798" "#e3d7ff" "#e4d7f5" "#e66550" "#e7e7e7"
    "#eaa041" "#ebdbde" "#efa093" "#efefef" "#f2b2a8" "#f2c960" "#f3f3f3" "#f691b2"
    "#f691b3" "#f6c5be" "#f7a7c0" "#fad165" "#fb4c2f" "#fbc8d9" "#fbd3e0" "#fbe983"
    "#fcda83" "#fcdee8" "#fce8b3" "#fdedc1" "#fef1d1" "#ff7537" "#ffad46" "#ffad47"
    "#ffbc6b" "#ffc8af" "#ffd6a2" "#ffdeb5" "#ffe6c7" "#ffffff"))

;; ============================================================================
;; Color Scheme Definitions
;; ============================================================================

;; Scheme metadata: (capacity colormap-symbol description)
(define SCHEMES
  (hash 'set1          (list 9  'set1        "ColorBrewer Set1 (9 colors)")
        'set2          (list 8  'set2        "ColorBrewer Set2 (8 colors)")
        'set3          (list 12 'set3        "ColorBrewer Set3 (12 colors)")
        'paired        (list 12 'paired      "ColorBrewer Paired (12 colors)")
        'dark2         (list 8  'dark2       "ColorBrewer Dark2 (8 colors)")
        'pastel1       (list 9  'pastel1     "ColorBrewer Pastel1 (9 colors)")
        'pastel2       (list 8  'pastel2     "ColorBrewer Pastel2 (8 colors)")
        'accent        (list 8  'cb-accent   "ColorBrewer Accent (8 colors)")
        'bright        (list 7  'tol-bq      "Paul Tol Bright (7 colors)")
        'high-contrast (list 5  'tol-hcq     "Paul Tol High Contrast (5 colors)")
        'vibrant       (list 7  'tol-vq      "Paul Tol Vibrant (7 colors)")
        'muted         (list 9  'tol-mq      "Paul Tol Muted (9 colors)")
        'pale          (list 6  'tol-pq      "Paul Tol Pale (6 colors)")
        'dark          (list 6  'tol-dq      "Paul Tol Dark (6 colors)")
        'light         (list 9  'tol-lq      "Paul Tol Light (9 colors)")
        'rainbow       (list #f 'rainbow     "Paul Tol Rainbow (unlimited)")))

;; Get scheme info
(define (scheme-info scheme-name)
  (hash-ref SCHEMES scheme-name #f))

;; ============================================================================
;; Color Distance (RGB Euclidean)
;; ============================================================================

(define (color-distance rgb1 rgb2)
  (match-define (list r1 g1 b1) rgb1)
  (match-define (list r2 g2 b2) rgb2)
  (sqrt (+ (expt (- r1 r2) 2)
           (expt (- g1 g2) 2)
           (expt (- b1 b2) 2))))

;; Convert hex to RGB (0-255 range)
(define (hex->rgb hex-string)
  (define hex (string-trim hex-string "#"))
  (list (string->number (substring hex 0 2) 16)
        (string->number (substring hex 2 4) 16)
        (string->number (substring hex 4 6) 16)))

;; Find nearest Gmail color to RGB
(define (rgb->gmail-color r g b)
  (argmin (λ (gmail-hex)
            (color-distance (list r g b) (hex->rgb gmail-hex)))
          GMAIL-PALETTE))

;; Calculate perceived brightness (0-255)
;; Using formula: 0.299*R + 0.587*G + 0.114*B
(define (perceived-brightness hex-color)
  (match-define (list r g b) (hex->rgb hex-color))
  (+ (* 0.299 r) (* 0.587 g) (* 0.114 b)))

;; Choose text color (black or white) based on background brightness
(define (text-color-for-background bg-hex)
  (if (> (perceived-brightness bg-hex) 128)
      "#000000"  ; Dark text for light backgrounds
      "#ffffff")) ; Light text for dark backgrounds

;; ============================================================================
;; Color Generation
;; ============================================================================

;; Get colors from a colormap scheme
(define (get-scheme-colors scheme-symbol num-colors)
  (cond
    [(eq? scheme-symbol 'rainbow)
     ;; Special case: generate exactly num-colors
     (make-tol-rainbow-colormap num-colors)]
    [else
     ;; Use parameterize to set colormap, then extract colors
     (parameterize ([plot-pen-color-map scheme-symbol])
       (for/list ([i num-colors])
         (define color-idx (modulo i num-colors))  ; Cycle if needed
         (match-define (list r g b) (->pen-color color-idx))
         (list r g b)))]))

;; Generate Gmail-compatible colors for N labels
(define (generate-label-colors scheme-name label-count)
  (define scheme-data (scheme-info scheme-name))
  
  (unless scheme-data
    (error 'generate-label-colors "Unknown color scheme: ~a" scheme-name))
  
  (match-define (list capacity colormap-symbol description) scheme-data)
  
  ;; Warn if cycling
  (when (and capacity (> label-count capacity))
    (displayln (format "⚠ Warning: ~a labels but scheme '~a' has only ~a colors"
                      label-count scheme-name capacity))
    (displayln (format "  Colors will cycle (repeat). Consider using 'rainbow for ~a distinct colors."
                      label-count)))
  
  ;; Get colormap RGB colors
  (define rgb-colors (get-scheme-colors colormap-symbol label-count))
  
  ;; Map to Gmail palette
  (for/list ([rgb rgb-colors])
    (match-define (list r g b) rgb)
    (rgb->gmail-color r g b)))
