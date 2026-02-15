# Label Color Assignment System

## Overview

Automatically assign visually distinct colors to Gmail labels using established color theory (ColorBrewer, Paul Tol) with fallback to dynamic rainbow generation.

## Design Decisions

### 1. Which Labels to Color
**Decision**: Color ALL user labels
- Simple, no complex queries needed
- Fast execution
- Config option to exclude specific labels if needed

### 2. Color Schemes

#### Available Qualitative Schemes

**ColorBrewer (Racket built-in `plot` package):**
- `set1` - 9 colors (default, well-tested)
- `set2` - 8 colors
- `set3` - 12 colors
- `paired` - 12 colors (alternating shades)
- `dark2` - 8 colors
- `pastel1` - 9 colors
- `pastel2` - 8 colors

**ColorBrewer (from `colormaps` package):**
- `accent` - 8 colors

**Paul Tol (from `colormaps` package):**
- `bright` - 7 colors (tol-bq)
- `high-contrast` - 5 colors (tol-hcq)
- `vibrant` - 7 colors (tol-vq)
- `muted` - 9 colors (tol-mq)
- `pale` - 6 colors (tol-pq)
- `dark` - 6 colors (tol-dq)
- `light` - 9 colors (tol-lq)

**Dynamic:**
- `rainbow` - Any N (uses `make-tol-rainbow-colormap`)

#### Scheme Selection Logic

```racket
(define (select-colors scheme-name label-count)
  ;; 1. Try requested scheme
  ;; 2. If label-count > scheme capacity → fallback to rainbow
  ;; 3. If label-count < scheme capacity → use first N colors
  )
```

**Fallback behavior when exceeding capacity:**
- Most schemes have fixed capacity (7-12 colors)
- If more labels than colors → automatically use `rainbow` with N=label-count
- Rainbow is special case: dynamically generates exactly N distinct colors

**Recycling (NOT USED):**
- We don't recycle/wrap around
- Better to use rainbow for consistency when exceeding capacity

#### English Names

All schemes have self-explanatory names:
- `set1`, `set2`, `set3` - ColorBrewer standard sets
- `paired` - Alternating light/dark pairs
- `bright`, `muted`, `vibrant`, `pale`, `dark`, `light` - Paul Tol descriptive names
- `accent` - ColorBrewer accent colors
- `rainbow` - Dynamic rainbow (special: takes label count)

### 3. Color Distance Algorithm
**Decision**: RGB Euclidean distance
- Simple, fast, "good enough" for our use case
- Formula: `sqrt((r1-r2)² + (g1-g2)² + (b1-b2)²)`
- Alternative (CIELAB) is more perceptually accurate but requires additional libraries

### 4. When to Assign Colors
**Decision**: Both automatic and manual
- **Automatic**: At end of every `process` run (if color-scheme configured)
- **Manual**: `schemail labels assign-colors` command
- CLI flag `--color-scheme` can override config for a single run

## Gmail Color Palette

Gmail supports **101 fixed background colors**:

```
#000000, #04502e, #076239, #094228, #0b4f30, #0b804b, #0d3472, #0d3b44,
#149e60, #16a765, #16a766, #1a764d, #1c4587, #285bac, #2a9c68, #2da2bb,
#3c78d8, #3d188e, #3dc789, #41236d, #42d692, #434343, #43d692, #44b984,
#464646, #4986e7, #4a86e8, #594c05, #653e9b, #662e37, #666666, #684e07,
#68dfa9, #6d9eeb, #711a36, #7a2e0b, #7a4706, #822111, #83334c, #89d3b2,
#8a1c0a, #8e63ce, #98d7e4, #994a64, #999999, #a0eac9, #a2dcc1, #a46a21,
#a479e2, #a4c2f4, #aa8831, #ac2b16, #b3efd3, #b65775, #b694e8, #b6cff5,
#b99aff, #b9e4d0, #c2c2c2, #c6f3de, #c9daf8, #cc3a21, #cca6ac, #cccccc,
#cf8933, #d0bcf1, #d5ae49, #e07798, #e3d7ff, #e4d7f5, #e66550, #e7e7e7,
#eaa041, #ebdbde, #efa093, #efefef, #f2b2a8, #f2c960, #f3f3f3, #f691b2,
#f691b3, #f6c5be, #f7a7c0, #fad165, #fb4c2f, #fbc8d9, #fbd3e0, #fbe983,
#fcda83, #fcdee8, #fce8b3, #fdedc1, #fef1d1, #ff7537, #ffad46, #ffad47,
#ffbc6b, #ffc8af, #ffd6a2, #ffdeb5, #ffe6c7, #ffffff
```

Colormap RGB values are mapped to nearest Gmail palette color using Euclidean distance.

## Implementation Plan

### 1. Color Utilities Module

**File**: `src/colors.rkt`

```racket
#lang racket

(require colormaps/tol
         colormaps/cb
         plot)

(provide generate-label-colors
         rgb->gmail-color
         GMAIL-PALETTE)

;; Gmail's 101 fixed colors
(define GMAIL-PALETTE
  '(#000000 #04502e #076239 #094228 ...))

;; Color distance (RGB Euclidean)
(define (color-distance rgb1 rgb2)
  (match-define (list r1 g1 b1) rgb1)
  (match-define (list r2 g2 b2) rgb2)
  (sqrt (+ (expt (- r1 r2) 2)
           (expt (- g1 g2) 2)
           (expt (- b1 b2) 2))))

;; Convert hex to RGB
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

;; Scheme definitions with capacity
(define SCHEMES
  (hash 'set1        (cons 9 'set1)
        'set2        (cons 8 'set2)
        'set3        (cons 12 'set3)
        'paired      (cons 12 'paired)
        'dark2       (cons 8 'dark2)
        'pastel1     (cons 9 'pastel1)
        'pastel2     (cons 8 'pastel2)
        'accent      (cons 8 'cb-accent)
        'bright      (cons 7 'tol-bq)
        'high-contrast (cons 5 'tol-hcq)
        'vibrant     (cons 7 'tol-vq)
        'muted       (cons 9 'tol-mq)
        'pale        (cons 6 'tol-pq)
        'dark        (cons 6 'tol-dq)
        'light       (cons 9 'tol-lq)
        'rainbow     (cons #f 'rainbow))) ; #f = unlimited

;; Generate colors for N labels
(define (generate-label-colors scheme-name label-count)
  ;; 1. Look up scheme
  ;; 2. If capacity < label-count → use rainbow
  ;; 3. Get colormap RGB colors
  ;; 4. Map to Gmail palette
  ;; 5. Return list of Gmail hex colors
  ...)
```

### 2. Configuration File

**File**: `config/schemail.rkt`

```racket
#lang racket

(provide (all-defined-out))

;; Color scheme for labels
;; Options: 'set1, 'set2, 'paired, 'muted, 'bright, 'rainbow, or #f to disable
;; Falls back to 'rainbow if more labels than scheme supports
(define color-scheme 'set1)

;; Labels to exclude from coloring (optional)
;; Example: '("ImportantProject" "PersonalStuff")
(define exclude-from-coloring '())

;; Helper to get config value
(define (get-config key)
  (case key
    [(color-scheme) color-scheme]
    [(exclude-from-coloring) exclude-from-coloring]
    [else #f]))
```

### 3. Label Coloring Integration

**File**: `src/label-colors.rkt`

```racket
#lang racket

(require "gmail.rkt"
         "colors.rkt"
         "../config/schemail.rkt")

(provide apply-label-colors!)

;; Apply colors to all user labels
(define (apply-label-colors! #:scheme [scheme (get-config 'color-scheme)])
  (when scheme
    ;; Get all user labels
    (define all-labels (gmail-list-labels))
    (define user-labels
      (filter (λ (label)
                (define name (hash-ref label 'name))
                (and (equal? (hash-ref label 'type) "user")
                     (not (equal? name "Schemail"))
                     (not (member name (get-config 'exclude-from-coloring)))))
              all-labels))
    
    ;; Generate colors
    (define label-names (map (λ (l) (hash-ref l 'name)) user-labels))
    (define colors (generate-label-colors scheme (length label-names)))
    
    ;; Apply colors
    (displayln (format "\n=== Applying ~a color scheme to ~a labels ==="
                      scheme (length label-names)))
    (for ([label user-labels] [color colors])
      (define label-id (hash-ref label 'id))
      (define label-name (hash-ref label 'name))
      (displayln (format "  ~a → ~a" label-name color))
      (gmail-update-label label-id #:background-color color))))
```

### 4. CLI Integration

**Update**: `bin/schemail`

```racket
;; Add to argument parsing
[(list "--color-scheme" scheme rest ...)
 (hash-set! options 'color-scheme (string->symbol scheme))
 (loop rest)]

;; Add to cmd-process (at end)
(define color-scheme-override (hash-ref options 'color-scheme #f))
(when (or color-scheme-override (get-config 'color-scheme))
  (apply-label-colors! #:scheme (or color-scheme-override 
                                     (get-config 'color-scheme))))

;; Add new command: labels assign-colors
[(list "labels" "assign-colors" rest ...)
 (hash-set! options 'command 'labels-assign-colors)
 (loop rest)]

(define (cmd-labels-assign-colors options)
  (displayln "\n╔════════════════════════════════════════════════════════════╗")
  (displayln "║  Assign Label Colors                                       ║")
  (displayln "╚════════════════════════════════════════════════════════════╝\n")
  
  (get-gmail-token)
  
  (define scheme-override (hash-ref options 'color-scheme #f))
  (define scheme (or scheme-override (get-config 'color-scheme)))
  
  (unless scheme
    (displayln "Error: No color scheme configured.")
    (displayln "Set 'color-scheme in config/schemail.rkt or use --color-scheme flag.")
    (exit 1))
  
  (apply-label-colors! #:scheme scheme)
  (displayln "\n✓ Label colors assigned!"))
```

### 5. Usage Examples

```bash
# Use default scheme from config
./bin/schemail process --last 50 --classifier experiment-1

# Override with specific scheme for this run
./bin/schemail process --last 50 --color-scheme muted

# Disable coloring for this run
./bin/schemail process --last 50 --color-scheme none

# Manually assign colors (uses config)
./bin/schemail labels assign-colors

# Manually assign colors (override)
./bin/schemail labels assign-colors --color-scheme bright

# Available schemes:
# ColorBrewer: set1 (9), set2 (8), set3 (12), paired (12), 
#              dark2 (8), pastel1 (9), pastel2 (8), accent (8)
# Paul Tol:    bright (7), muted (9), vibrant (7), light (9),
#              pale (6), dark (6), high-contrast (5)
# Dynamic:     rainbow (any N)
```

## Testing Plan

1. **Small label set (< 5)**
   - Test with `bright`, `set1`
   - Verify colors are distinct

2. **Medium label set (5-12)**
   - Test with `set3`, `paired`, `muted`
   - Verify no fallback to rainbow

3. **Large label set (> 12)**
   - Test with `set1` → should fallback to rainbow
   - Verify rainbow generates N colors

4. **Color mapping accuracy**
   - Compare colormap RGB → Gmail hex mapping
   - Visual inspection in Gmail UI

5. **Exclusion list**
   - Add label to `exclude-from-coloring`
   - Verify it keeps original color

## Future Enhancements

1. **CIELAB color distance** - More perceptually accurate matching
2. **Custom color schemes** - User-defined color lists
3. **Per-label color pinning** - Lock specific label colors
4. **Color theme export/import** - Share schemes between users
5. **Schemail-only detection** - Only color labels created by schemail (complex, may not be worth it)

## References

- [ColorBrewer 2.0](https://colorbrewer2.org/) - Evidence-based color schemes
- [Paul Tol's Color Schemes](https://personal.sron.nl/~pault/) - Scientific visualization colors
- [Racket colormaps package](https://docs.racket-lang.org/colormaps/index.html)
- [Gmail Labels API](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels)
