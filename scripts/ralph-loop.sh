#!/bin/bash
#
# Ralph Loop for Claude Code
#
# Based on Geoffrey Huntley's Ralph Wiggum methodology:
# https://github.com/ghuntley/how-to-ralph-wiggum
#
# Combined with SpecKit-style specifications.
#
# Key principles:
# - Each iteration picks ONE task/spec to work on
# - Agent works until acceptance criteria are met
# - Only outputs <promise>DONE</promise> when truly complete
# - Bash loop checks for magic phrase before continuing
# - Fresh context window each iteration
#
# Work sources (in priority order):
# 1. IMPLEMENTATION_PLAN.md (if exists) - pick highest priority task
# 2. specs/ folder - pick highest priority incomplete spec
#
# Usage:
#   ./scripts/ralph-loop.sh              # Build mode (unlimited)
#   ./scripts/ralph-loop.sh 20           # Build mode (max 20 iterations)
#   ./scripts/ralph-loop.sh plan         # Planning mode (creates IMPLEMENTATION_PLAN.md)
#

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
CONSTITUTION="$PROJECT_DIR/.specify/memory/constitution.md"
RLM_DIR="$PROJECT_DIR/rlm"
RLM_TRACE_DIR="$RLM_DIR/trace"
RLM_QUERIES_DIR="$RLM_DIR/queries"
RLM_ANSWERS_DIR="$RLM_DIR/answers"
RLM_INDEX="$RLM_DIR/index.tsv"

# Configuration
MAX_ITERATIONS=0  # 0 = unlimited
MODE="build"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
YOLO_FLAG="--dangerously-skip-permissions"
RLM_CONTEXT_FILE=""
TAIL_LINES=5
TAIL_RENDERED_LINES=0
ROLLING_OUTPUT_LINES=5
ROLLING_OUTPUT_INTERVAL=10
ROLLING_RENDERED_LINES=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

# Check constitution for YOLO setting
YOLO_ENABLED=true
if [[ -f "$CONSTITUTION" ]]; then
    if grep -q "YOLO Mode.*DISABLED" "$CONSTITUTION" 2>/dev/null; then
        YOLO_ENABLED=false
    fi
fi

show_help() {
    cat <<EOF
Ralph Loop for Claude Code

Based on Geoffrey Huntley's Ralph Wiggum methodology + SpecKit specs.
https://github.com/ghuntley/how-to-ralph-wiggum

Usage:
  ./scripts/ralph-loop.sh              # Build mode, unlimited iterations
  ./scripts/ralph-loop.sh 20           # Build mode, max 20 iterations  
  ./scripts/ralph-loop.sh plan         # Planning mode (optional)
  ./scripts/ralph-loop.sh --rlm-context ./rlm/context.txt
  ./scripts/ralph-loop.sh --rlm ./rlm/context.txt

Modes:
  build (default)  Pick spec/task and implement
  plan             Create IMPLEMENTATION_PLAN.md from specs (OPTIONAL)

Work Sources (checked in order):
  1. IMPLEMENTATION_PLAN.md - If exists, pick highest priority task
  2. specs/ folder - Otherwise, pick highest priority incomplete spec

The plan mode is OPTIONAL. Most projects can work directly from specs.

RLM Mode (optional):
  --rlm-context <file>  Treat a large context file as external environment.
                        The agent should read slices instead of loading it all.
  --rlm [file]          Shortcut for --rlm-context (defaults to rlm/context.txt)

How it works:
  1. Each iteration feeds PROMPT.md to Claude via stdin
  2. Claude picks the HIGHEST PRIORITY incomplete spec/task
  3. Claude implements, tests, and verifies acceptance criteria
  4. Claude outputs <promise>DONE</promise> ONLY if criteria are met
  5. Bash loop checks for the magic phrase
  6. If found, loop continues to next iteration (fresh context)
  7. If not found, loop retries

RLM workspace (when enabled):
  - rlm/trace/     Prompt snapshots + outputs per iteration
  - rlm/index.tsv  Index of all iterations (timestamp, prompt, log, status)
  - rlm/queries/ and rlm/answers/  For optional recursive sub-queries

EOF
}

print_latest_output() {
    local log_file="$1"
    local label="${2:-Claude}"
    local target="/dev/tty"

    [ -f "$log_file" ] || return 0

    if [ ! -w "$target" ]; then
        target="/dev/stdout"
    fi

    if [ "$target" = "/dev/tty" ] && [ "$TAIL_RENDERED_LINES" -gt 0 ]; then
        printf "\033[%dA\033[J" "$TAIL_RENDERED_LINES" > "$target"
    fi

    {
        echo "Latest ${label} output (last ${TAIL_LINES} lines):"
        tail -n "$TAIL_LINES" "$log_file"
    } > "$target"

    if [ "$target" = "/dev/tty" ]; then
        TAIL_RENDERED_LINES=$((TAIL_LINES + 1))
    fi
}

watch_latest_output() {
    local log_file="$1"
    local label="${2:-Claude}"
    local target="/dev/tty"
    local use_tty=false
    local use_tput=false

    [ -f "$log_file" ] || return 0

    if [ ! -w "$target" ]; then
        target="/dev/stdout"
    else
        use_tty=true
        if command -v tput &>/dev/null; then
            use_tput=true
        fi
    fi

    if [ "$use_tty" = true ]; then
        if [ "$use_tput" = true ]; then
            tput cr > "$target"
            tput sc > "$target"
        else
            printf "\r\0337" > "$target"
        fi
    fi

    while true; do
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        if [ "$use_tty" = true ]; then
            if [ "$use_tput" = true ]; then
                tput rc > "$target"
                tput ed > "$target"
                tput cr > "$target"
            else
                printf "\0338\033[J\r" > "$target"
            fi
        fi

        {
            echo -e "${CYAN}[$timestamp] Latest ${label} output (last ${ROLLING_OUTPUT_LINES} lines):${NC}"
            if [ ! -s "$log_file" ]; then
                echo "(no output yet)"
            else
                tail -n "$ROLLING_OUTPUT_LINES" "$log_file" 2>/dev/null || true
            fi
            echo ""
        } > "$target"

        sleep "$ROLLING_OUTPUT_INTERVAL"
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        plan)
            MODE="plan"
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                MAX_ITERATIONS="$2"
                shift 2
            else
                MAX_ITERATIONS=1
                shift
            fi
            ;;
        --rlm-context)
            RLM_CONTEXT_FILE="${2:-}"
            shift 2
            ;;
        --rlm)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                RLM_CONTEXT_FILE="$2"
                shift 2
            else
                RLM_CONTEXT_FILE="rlm/context.txt"
                shift
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        [0-9]*)
            MODE="build"
            MAX_ITERATIONS="$1"
            shift
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

# Validate RLM context file (if provided)
if [ -n "$RLM_CONTEXT_FILE" ] && [ ! -f "$RLM_CONTEXT_FILE" ]; then
    echo -e "${RED}Error: RLM context file not found: $RLM_CONTEXT_FILE${NC}"
    echo "Create it first (example):"
    echo "  mkdir -p rlm && printf \"%s\" \"<your long context>\" > $RLM_CONTEXT_FILE"
    exit 1
fi

# Initialize RLM workspace (optional)
if [ -n "$RLM_CONTEXT_FILE" ]; then
    mkdir -p "$RLM_TRACE_DIR" "$RLM_QUERIES_DIR" "$RLM_ANSWERS_DIR"
    if [ ! -f "$RLM_INDEX" ]; then
        echo -e "timestamp\tmode\titeration\tprompt\tlog\toutput\tstatus" > "$RLM_INDEX"
    fi
fi

# Session log (captures ALL output)
SESSION_LOG="$LOG_DIR/ralph_${MODE}_session_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$SESSION_LOG") 2>&1

# Check if Claude CLI is available
if ! command -v "$CLAUDE_CMD" &> /dev/null; then
    echo -e "${RED}Error: Claude CLI not found${NC}"
    echo ""
    echo "Install Claude Code CLI and authenticate first."
    echo "https://claude.ai/code"
    exit 1
fi

# Determine which prompt to use based on mode and available files
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="PROMPT_plan.md"
else
    PROMPT_FILE="PROMPT_build.md"
fi

# Create/update the build prompt to be flexible about plan vs specs
cat > "PROMPT_build.md" << 'BUILDEOF'
# Ralph Build Mode

Based on Geoffrey Huntley's Ralph Wiggum methodology.

---

## Phase 0: Orient

0a. Read `.specify/memory/constitution.md` for project principles.

0b. Study `specs/` to understand feature specifications.

0c. Check if `IMPLEMENTATION_PLAN.md` exists.

---
BUILDEOF

# Optional RLM context block
if [ -n "$RLM_CONTEXT_FILE" ]; then
cat >> "PROMPT_build.md" << EOF

## Phase 0d: RLM Context (Optional)

You have access to a large context file at:
**$RLM_CONTEXT_FILE**

Treat this file as an external environment. Do NOT paste the whole file into the prompt.
Instead, inspect it programmatically and recursively:

- Use small slices:
  ```bash
  sed -n 'START,ENDp' "$RLM_CONTEXT_FILE"
  ```
- Or Python snippets:
  ```bash
  python - <<'PY'
  from pathlib import Path
  p = Path("$RLM_CONTEXT_FILE")
  print(p.read_text().splitlines()[START:END])
  PY
  ```
- Use search:
  ```bash
  rg -n "pattern" "$RLM_CONTEXT_FILE"
  ```

Goal: decompose the task into smaller sub-queries and only load the pieces you need.
This mirrors the Recursive Language Model approach from https://arxiv.org/html/2512.24601v1

## RLM Workspace (Optional)

Past loop outputs are preserved on disk:
- Iteration logs: `logs/`
- Prompt/output snapshots: `rlm/trace/`
- Iteration index: `rlm/index.tsv`

Use these as an external memory store (search/slice as needed).
If you need a recursive sub-query, write a focused prompt in `rlm/queries/`,
run:
  `./scripts/rlm-subcall.sh --query rlm/queries/<file>.md`
and store the result in `rlm/answers/`.
EOF
fi

cat >> "PROMPT_build.md" << 'BUILDEOF'

## Phase 1: Select Work Item

### If IMPLEMENTATION_PLAN.md exists:
Pick the **HIGHEST PRIORITY** incomplete task from the plan.

### If NO plan exists (preferred simple approach):
Look at `specs/` folder and pick the **HIGHEST PRIORITY** spec that:
- Is NOT marked as complete (no `[x] DONE` or similar in the spec)
- Has incomplete acceptance criteria
- Has the highest priority (lower number = higher priority, e.g., 001 before 010)

Before implementing, search the codebase — don't assume it's not done.

---

## Phase 2: Implement

Implement the selected spec/task completely:
- Follow the spec's requirements exactly
- Write clean, maintainable code
- Add tests as needed
- Mark the spec as complete when done

---

## Phase 3: Validate

Run the project's test suite and verify:
- All tests pass
- No lint errors
- The spec's acceptance criteria are 100% met

---

## Phase 4: Commit & Update

1. If using IMPLEMENTATION_PLAN.md, update it to mark task complete
2. If working directly from specs, add `## Status: COMPLETE` to the spec file
3. `git add -A`
4. `git commit` with a descriptive message
5. `git push`

---

## Completion Signal

**CRITICAL:** Only output the magic phrase when the spec/task is 100% complete.

Check:
- [ ] Implementation matches all requirements
- [ ] All tests pass
- [ ] All acceptance criteria verified
- [ ] Changes committed and pushed
- [ ] Spec marked as complete

**If ALL checks pass, output:** `<promise>DONE</promise>`

**If ANY check fails:** Fix the issue and try again. Do NOT output the magic phrase.
BUILDEOF

# Create planning prompt (only used if plan mode is explicitly requested)
cat > "PROMPT_plan.md" << 'PLANEOF'
# Ralph Planning Mode (OPTIONAL)

This mode is OPTIONAL. Most projects work fine directly from specs.

Only use this when you want a detailed breakdown of specs into smaller tasks.

---

## Phase 0: Orient

0a. Read `.specify/memory/constitution.md` for project principles.

0b. Study `specs/` to learn all feature specifications.

---
PLANEOF

# Optional RLM context block for planning
if [ -n "$RLM_CONTEXT_FILE" ]; then
cat >> "PROMPT_plan.md" << EOF

## Phase 0c: RLM Context (Optional)

You have access to a large context file at:
**$RLM_CONTEXT_FILE**

Treat this file as an external environment. Do NOT paste the whole file into the prompt.
Inspect only the slices you need using shell tools or Python.
This mirrors the Recursive Language Model approach from https://arxiv.org/html/2512.24601v1

## RLM Workspace (Optional)

Past loop outputs are preserved on disk:
- Iteration logs: `logs/`
- Prompt/output snapshots: `rlm/trace/`
- Iteration index: `rlm/index.tsv`

Use these as an external memory store (search/slice as needed).
For recursive sub-queries, use:
  `./scripts/rlm-subcall.sh --query rlm/queries/<file>.md`
EOF
fi

cat >> "PROMPT_plan.md" << 'PLANEOF'

## Phase 1: Gap Analysis

Compare specs against current codebase:
- What's fully implemented?
- What's partially done?
- What's not started?
- What has issues or bugs?

---

## Phase 2: Create Plan

Create `IMPLEMENTATION_PLAN.md` with a prioritized task list:

```markdown
# Implementation Plan

> Auto-generated breakdown of specs into tasks.
> Delete this file to return to working directly from specs.

## Priority Tasks

- [ ] [HIGH] Task description - from spec NNN
- [ ] [HIGH] Task description - from spec NNN  
- [ ] [MEDIUM] Task description
- [ ] [LOW] Task description

## Completed

- [x] Completed task
```

Prioritize by:
1. Dependencies (do prerequisites first)
2. Impact (high-value features first)
3. Complexity (mix easy wins with harder tasks)

---

## Completion Signal

When the plan is complete and saved:

`<promise>DONE</promise>`
PLANEOF

# Check prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: $PROMPT_FILE not found${NC}"
    exit 1
fi

# Build Claude flags
CLAUDE_FLAGS="-p"
if [ "$YOLO_ENABLED" = true ]; then
    CLAUDE_FLAGS="$CLAUDE_FLAGS $YOLO_FLAG"
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Check for work sources - count .md files in specs/
HAS_PLAN=false
HAS_SPECS=false
SPEC_COUNT=0
[ -f "IMPLEMENTATION_PLAN.md" ] && HAS_PLAN=true
if [ -d "specs" ]; then
    SPEC_COUNT=$(find specs -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l)
    [ "$SPEC_COUNT" -gt 0 ] && HAS_SPECS=true
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}              RALPH LOOP (Claude Code) STARTING              ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Mode:${NC}     $MODE"
echo -e "${BLUE}Prompt:${NC}   $PROMPT_FILE"
echo -e "${BLUE}Branch:${NC}   $CURRENT_BRANCH"
echo -e "${YELLOW}YOLO:${NC}     $([ "$YOLO_ENABLED" = true ] && echo "ENABLED" || echo "DISABLED")"
[ -n "$RLM_CONTEXT_FILE" ] && echo -e "${BLUE}RLM:${NC}      $RLM_CONTEXT_FILE"
[ -n "$SESSION_LOG" ] && echo -e "${BLUE}Log:${NC}      $SESSION_LOG"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${BLUE}Max:${NC}      $MAX_ITERATIONS iterations"
echo ""
echo -e "${BLUE}Work source:${NC}"
if [ "$HAS_PLAN" = true ]; then
    echo -e "  ${GREEN}✓${NC} IMPLEMENTATION_PLAN.md (will use this)"
else
    echo -e "  ${YELLOW}○${NC} IMPLEMENTATION_PLAN.md (not found, that's OK)"
fi
if [ "$HAS_SPECS" = true ]; then
    echo -e "  ${GREEN}✓${NC} specs/ folder ($SPEC_COUNT specs)"
else
    echo -e "  ${RED}✗${NC} specs/ folder (no .md files found)"
fi
echo ""
echo -e "${CYAN}The loop checks for <promise>DONE</promise> in each iteration.${NC}"
echo -e "${CYAN}Agent must verify acceptance criteria before outputting it.${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the loop${NC}"
echo ""

ITERATION=0
CONSECUTIVE_FAILURES=0
MAX_CONSECUTIVE_FAILURES=3

while true; do
    # Check max iterations
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo -e "${GREEN}Reached max iterations: $MAX_ITERATIONS${NC}"
        break
    fi

    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo -e "${PURPLE}════════════════════ LOOP $ITERATION ════════════════════${NC}"
    echo -e "${BLUE}[$TIMESTAMP]${NC} Starting iteration $ITERATION"
    echo ""

    # Log file for this iteration
    LOG_FILE="$LOG_DIR/ralph_${MODE}_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').log"
    : > "$LOG_FILE"
    WATCH_PID=""

    if [ "$ROLLING_OUTPUT_INTERVAL" -gt 0 ] && [ "$ROLLING_OUTPUT_LINES" -gt 0 ] && [ -t 1 ] && [ -w /dev/tty ]; then
        watch_latest_output "$LOG_FILE" "Claude" &
        WATCH_PID=$!
    fi
    RLM_STATUS="unknown"

    # Snapshot prompt (optional RLM workspace)
    if [ -n "$RLM_CONTEXT_FILE" ]; then
        RLM_PROMPT_SNAPSHOT="$RLM_TRACE_DIR/iter_${ITERATION}_prompt.md"
        cp "$PROMPT_FILE" "$RLM_PROMPT_SNAPSHOT"
    fi

    # Run Claude with prompt via stdin, capture output
    CLAUDE_OUTPUT=""
    if CLAUDE_OUTPUT=$(cat "$PROMPT_FILE" | "$CLAUDE_CMD" $CLAUDE_FLAGS 2>&1 | tee "$LOG_FILE"); then
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo ""
        echo -e "${GREEN}✓ Claude execution completed${NC}"
        
        # Check if DONE promise was output
        if echo "$CLAUDE_OUTPUT" | grep -q "<promise>DONE</promise>"; then
            echo -e "${GREEN}✓ Completion signal detected: <promise>DONE</promise>${NC}"
            echo -e "${GREEN}✓ Task completed successfully!${NC}"
            CONSECUTIVE_FAILURES=0
            RLM_STATUS="done"
            
            # For planning mode, stop after one successful plan
            if [ "$MODE" = "plan" ]; then
                echo ""
                echo -e "${GREEN}Planning complete!${NC}"
                echo -e "${CYAN}Run './scripts/ralph-loop.sh' to start building.${NC}"
                echo -e "${CYAN}Or delete IMPLEMENTATION_PLAN.md to work directly from specs.${NC}"
                break
            fi
        else
            echo -e "${YELLOW}⚠ No completion signal found${NC}"
            echo -e "${YELLOW}  Agent did not output <promise>DONE</promise>${NC}"
            echo -e "${YELLOW}  This means acceptance criteria were not met.${NC}"
            echo -e "${YELLOW}  Retrying in next iteration...${NC}"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            RLM_STATUS="incomplete"
            print_latest_output "$LOG_FILE" "Claude"
            
            if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
                echo ""
                echo -e "${RED}⚠ $MAX_CONSECUTIVE_FAILURES consecutive iterations without completion.${NC}"
                echo -e "${RED}  The agent may be stuck. Consider:${NC}"
                echo -e "${RED}  - Checking the logs in $LOG_DIR${NC}"
                echo -e "${RED}  - Simplifying the current spec${NC}"
                echo -e "${RED}  - Manually fixing blocking issues${NC}"
                echo ""
                CONSECUTIVE_FAILURES=0
            fi
        fi
    else
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo -e "${RED}✗ Claude execution failed${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        RLM_STATUS="error"
        print_latest_output "$LOG_FILE" "Claude"
    fi

    # Record iteration in RLM index (optional)
    if [ -n "$RLM_CONTEXT_FILE" ]; then
        RLM_PROMPT_PATH="${RLM_PROMPT_SNAPSHOT:-}"
        RLM_OUTPUT_SNAPSHOT="$RLM_TRACE_DIR/iter_${ITERATION}_output.log"
        cp "$LOG_FILE" "$RLM_OUTPUT_SNAPSHOT"
        echo -e "${TIMESTAMP}\t${MODE}\t${ITERATION}\t${RLM_PROMPT_PATH}\t${LOG_FILE}\t${RLM_OUTPUT_SNAPSHOT}\t${RLM_STATUS}" >> "$RLM_INDEX"
    fi

    # Push changes after each iteration (if any)
    git push origin "$CURRENT_BRANCH" 2>/dev/null || {
        if git log origin/$CURRENT_BRANCH..HEAD --oneline 2>/dev/null | grep -q .; then
            echo -e "${YELLOW}Push failed, creating remote branch...${NC}"
            git push -u origin "$CURRENT_BRANCH" 2>/dev/null || true
        fi
    }

    # Brief pause between iterations
    echo ""
    echo -e "${BLUE}Waiting 2s before next iteration...${NC}"
    sleep 2
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}         RALPH LOOP FINISHED ($ITERATION iterations)         ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
