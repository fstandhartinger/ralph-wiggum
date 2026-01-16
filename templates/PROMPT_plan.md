# Ralph Planning Mode

Based on Geoffrey Huntley's Ralph Wiggum methodology.
https://github.com/ghuntley/how-to-ralph-wiggum

---

## Phase 0: Orient

0a. Study `specs/*` to learn the application specifications. Each spec defines requirements for a feature.

0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.

0c. Study `.specify/memory/constitution.md` for project principles and configuration (if present).

0d. For reference, the application source code is in `src/*`.

---

## Phase 1: Gap Analysis & Planning

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and study existing source code in `src/*` and compare it against `specs/*`. 

   Analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a bullet point list sorted in priority of items yet to be implemented.

   Consider:
   - TODOs in code
   - Minimal implementations or placeholders
   - Skipped or flaky tests
   - Inconsistent patterns
   - Missing features from specs
   - Acceptance criteria not yet met

   Keep @IMPLEMENTATION_PLAN.md up to date with items considered complete/incomplete.

---

## Rules

IMPORTANT: Plan only. Do NOT implement anything.

Do NOT assume functionality is missing; confirm with code search first.

---

## Ultimate Goal

Analyze all specifications in `specs/` and create a comprehensive, prioritized implementation plan.

If an element is missing, search first to confirm it doesn't exist, then if needed author the specification.

If you create a new element then document the plan to implement it in @IMPLEMENTATION_PLAN.md.

---

## Completion

When planning is complete, output: `<promise>DONE</promise>`
