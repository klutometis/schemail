#lang racket

;; Basic hello world to verify Racket installation

(displayln "Hello, Scheme!")
(displayln "Racket 9.0 is ready to roll.")

;; Test some basic Racket features
(define (factorial n)
  (if (<= n 1)
      1
      (* n (factorial (- n 1)))))

(printf "Factorial of 5 is: ~a\n" (factorial 5))

;; Test HTTP client (we'll need this for Gmail API)
(require net/url)
(displayln "\nHTTP libraries loaded successfully!")
