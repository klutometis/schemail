#lang racket

;; Email filter configuration
;; This file defines the filters to apply to incoming emails

(require "../config/preferences.rkt")

;; Example filters combining rule-based and LLM approaches

;; ============================================================================
;; Strategy: Fast Pattern Matching + LLM Fallback (Recommended)
;; ============================================================================

(define filters-hybrid
  '(
    ;; Fast pattern matching for obvious cases (instant, free)
    (filter (from "noreply@github.com")
            (label "github")
            (archive)
            (skip))
    
    (filter (from "notifications@github.com")
            (label "github")
            (archive)
            (skip))
    
    (filter (and (from "anthropic.com")
                 (subject-contains "receipt"))
            (label "receipts")
            (mark-read)
            (skip))
    
    ;; LLM agent handles everything else (smart, ~$0.006/email)
    (filter (always)
            (llm-agent simple-agent-prompt))
    ))

;; ============================================================================
;; Strategy: Pure Agentic (LLM does everything)
;; ============================================================================

(define filters-pure-llm
  '(
    ;; Process ALL emails with LLM
    (filter (always)
            (llm-agent simple-agent-prompt))
    ))

;; ============================================================================
;; Strategy: Selective LLM (Only for ambiguous cases)
;; ============================================================================

(define filters-selective-llm
  '(
    ;; Clear automated senders
    (filter (or (from "noreply@")
                (from "no-reply@")
                (from "notifications@"))
            (label "notification")
            (archive)
            (mark-read)
            (skip))
    
    ;; Known important senders
    (filter (or (from "investor@example.com")
                (from "cofounder@example.com"))
            (label "action")
            (star)
            (skip))
    
    ;; Use LLM only for ambiguous cases
    (filter (not (or (has-label "notification")
                     (has-label "action")))
            (llm-agent simple-agent-prompt))
    ))

;; ============================================================================
;; Active Filter Set
;; ============================================================================

;; Choose which strategy to use:
(define active-filters filters-hybrid)  ; Change this to switch strategies

;; Export
(provide active-filters
         filters-hybrid
         filters-pure-llm
         filters-selective-llm)
