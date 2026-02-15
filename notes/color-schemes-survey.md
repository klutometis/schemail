# Color Schemes Survey

Complete survey of qualitative (categorical) color schemes available in Racket.

## Built-in Plot Package

These are available without installing `colormaps` package:

| Scheme Name | Colors | Description |
|-------------|--------|-------------|
| `set1` | 9 | ColorBrewer - Maximum distinction, bright |
| `set2` | 8 | ColorBrewer - Softer than Set1 |
| `set3` | 12 | ColorBrewer - Pastel, maximum capacity |
| `paired` | 12 | ColorBrewer - Alternating light/dark pairs |
| `dark2` | 8 | ColorBrewer - Darker variants |
| `pastel1` | 9 | ColorBrewer - Light, soft colors |
| `pastel2` | 8 | ColorBrewer - Even lighter pastels |

## ColorBrewer (colormaps package)

Requires: `(require colormaps/cb)`

| Scheme Name | Colors | Racket Symbol | Description |
|-------------|--------|---------------|-------------|
| Accent | 8 | `cb-accent` | Bright accent colors |

## Paul Tol (colormaps package)

Requires: `(require colormaps/tol)`

| Scheme Name | Colors | Racket Symbol | Description |
|-------------|--------|---------------|-------------|
| Bright | 7 | `tol-bq` | Maximum contrast, vivid |
| High Contrast | 5 | `tol-hcq` | Highest distinction, limited palette |
| Vibrant | 7 | `tol-vq` | Energetic, saturated |
| Muted | 9 | `tol-mq` | Softer, professional |
| Pale | 6 | `tol-pq` | Very light, subtle |
| Dark | 6 | `tol-dq` | Deep, rich tones |
| Light | 9 | `tol-lq` | Bright but soft |

## Dynamic Rainbow (Paul Tol)

Requires: `(require colormaps/tol)`

| Scheme Name | Colors | Function | Description |
|-------------|--------|----------|-------------|
| Rainbow | Any N | `(make-tol-rainbow-colormap N)` | Dynamically generates N distinct colors |

**Note**: Rainbow quality:
- Up to 29 colors: Selected from discrete palette (high quality)
- 30+ colors: Interpolated (may be less distinct)

## Recommended Defaults by Label Count

| Label Count | Recommended Scheme | Capacity | Notes |
|-------------|-------------------|----------|-------|
| 1-5 | `bright` or `high-contrast` | 5-7 | Maximum distinction |
| 6-8 | `set1` or `muted` | 8-9 | Well-tested, balanced |
| 9-12 | `set3` or `paired` | 12 | Good variety |
| 13+ | `rainbow` | Unlimited | Automatic generation |

## Color Theory Considerations

### ColorBrewer Philosophy
- **Evidence-based**: Tested for colorblind-safe, print-friendly, photocopy-safe
- **Categorical schemes**: Designed for nominal/categorical data (perfect for labels)
- **Maximum distinction**: Colors chosen to be maximally different

### Paul Tol Philosophy
- **Scientific visualization**: Optimized for data visualization
- **Perceptually distinct**: Based on color science research
- **Accessibility**: Colorblind-friendly options (High Contrast)

### Rainbow Fallback
- **Mathematical distribution**: Uses HSV color space to maximize perceptual distance
- **Scalable**: Works for any N
- **Trade-off**: Less "curated" than fixed palettes but guarantees uniqueness

## Human-Friendly Names

Mapping for config file and CLI:

```racket
;; Built-in schemes (no package needed)
'set1           → Maximum distinction (9 colors)
'set2           → Soft distinction (8 colors)  
'set3           → Maximum capacity (12 colors)
'paired         → Light/dark pairs (12 colors)
'dark2          → Dark variants (8 colors)
'pastel1        → Light pastels (9 colors)
'pastel2        → Very light (8 colors)

;; ColorBrewer extended (requires colormaps/cb)
'accent         → Accent colors (8 colors)

;; Paul Tol (requires colormaps/tol)
'bright         → Vivid, high contrast (7 colors)
'high-contrast  → Maximum distinction (5 colors)
'vibrant        → Energetic (7 colors)
'muted          → Professional (9 colors)
'pale           → Subtle (6 colors)
'dark           → Rich tones (6 colors)
'light          → Bright soft (9 colors)

;; Dynamic (requires colormaps/tol)
'rainbow        → Any number (unlimited)
```

## Implementation Notes

### Accessing Colors

**Built-in schemes:**
```racket
(require plot)
(parameterize ([plot-pen-color-map 'set1])
  (->pen-color 0))  ; Get first color
```

**Colormaps package:**
```racket
(require colormaps/tol colormaps/cb)
(parameterize ([plot-pen-color-map 'tol-mq])
  (->pen-color 0))

(make-tol-rainbow-colormap 15)  ; Generate 15 colors
```

### Capacity Checking

```racket
(define SCHEME-CAPACITIES
  (hash 'set1 9
        'set2 8
        'set3 12
        'paired 12
        'dark2 8
        'pastel1 9
        'pastel2 8
        'accent 8
        'bright 7
        'high-contrast 5
        'vibrant 7
        'muted 9
        'pale 6
        'dark 6
        'light 9
        'rainbow #f))  ; #f = unlimited
```

### Fallback Logic

```racket
(define (select-scheme scheme-name label-count)
  (define capacity (hash-ref SCHEME-CAPACITIES scheme-name #f))
  (cond
    [(not capacity) 'rainbow]  ; Unknown scheme → rainbow
    [(eq? scheme-name 'rainbow) 'rainbow]  ; Rainbow is rainbow
    [(< label-count capacity) scheme-name]  ; Fits in scheme
    [else 'rainbow]))  ; Exceeds capacity → fallback
```

## Visual Examples from Documentation

### ColorBrewer Set1 (9 colors)
![Set1](https://colorbrewer2.org/#type=qualitative&scheme=Set1&n=9)
- Red, Blue, Green, Purple, Orange, Yellow, Brown, Pink, Gray
- Default recommendation for most use cases

### Paul Tol Muted (9 colors)
- Rose, Indigo, Sand, Green, Cyan, Wine, Teal, Olive, Purple
- Professional appearance, works well in UI contexts

### Rainbow (Dynamic)
- Distributed across hue spectrum
- Generated algorithmically for any N
- Best for >12 categories where no fixed palette fits

## Testing Checklist

- [ ] Test each scheme with appropriate label count
- [ ] Verify fallback to rainbow when exceeding capacity
- [ ] Visual inspection in Gmail UI
- [ ] Test with colorblind simulation tools
- [ ] Compare RGB → Gmail hex mapping accuracy
- [ ] Test exclude-from-coloring config option
