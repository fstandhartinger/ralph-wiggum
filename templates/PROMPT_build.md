# Ralph Build Mode

Based on Geoffrey Huntley's Ralph Wiggum methodology.
https://github.com/ghuntley/how-to-ralph-wiggum

---

## Phase 0: Orient

0a. Study `specs/*` to learn the application specifications. Each spec defines requirements for a feature.

0b. Study @IMPLEMENTATION_PLAN.md to understand the current plan and what needs to be done.

0c. Study `.specify/memory/constitution.md` for project principles and configuration (if present).

0d. For reference, the application source code is in `src/*`.

---

## Phase 1: Select Task

Follow @IMPLEMENTATION_PLAN.md and choose the MOST IMPORTANT item to address.

Before making changes, search the codebase — don't assume functionality is not implemented.

---

## Phase 2: Implement

Implement the selected functionality per the specifications.

- Run tests to verify your changes work
- Check for any lint or type errors
- Fix any issues before proceeding

---

## Phase 3: Validate

After implementing functionality, run the project's validation commands.

If functionality is missing then it's your job to add it per the specifications.

---

## Phase 4: Update & Commit

1. When you discover issues, immediately update @IMPLEMENTATION_PLAN.md with your findings.
2. When resolved, update and remove the item from the plan.
3. When the tests pass:
   - Update @IMPLEMENTATION_PLAN.md
   - `git add -A`
   - `git commit` with a message describing the changes
   - `git push`

---

## Guardrails (Higher number = More Critical)

99999. Important: When authoring documentation, capture the why — tests and implementation importance.

999999. Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.

9999999. As soon as there are no build or test errors, consider creating a git tag for versioning.

99999999. You may add extra logging if required to debug issues.

999999999. Keep @IMPLEMENTATION_PLAN.md current with learnings — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.

9999999999. When you learn something new about how to run the application, update @AGENTS.md but keep it brief.

99999999999. For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.md even if unrelated to current work.

999999999999. Implement functionality completely. Placeholders and stubs waste efforts and time.

9999999999999. When @IMPLEMENTATION_PLAN.md becomes large, periodically clean out completed items.

99999999999999. IMPORTANT: Keep @AGENTS.md operational only — status updates and progress notes belong in @IMPLEMENTATION_PLAN.md. A bloated AGENTS.md pollutes every future loop's context.

---

## Completion

When your task is complete (tests pass, committed, pushed), output: `<promise>DONE</promise>`
