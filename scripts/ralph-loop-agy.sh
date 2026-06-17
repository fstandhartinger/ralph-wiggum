#!/bin/bash
#
# Ralph Loop for Antigravity CLI (agy)
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
#   ./scripts/ralph-loop-agy.sh                      # Build mode (unlimited)
#   ./scripts/ralph-loop-agy.sh 20                   # Build mode (max 20 iterations)
#   ./scripts/ralph-loop-agy.sh plan                 # Planning mode (creates IMPLEMENTATION_PLAN.md)
#   ./scripts/ralph-loop-agy.sh --model "model-name" # Override model
#
# Requirements:
#   - Antigravity CLI (agy) installed
#   - See: https://github.com/google-deepmind/antigravity
#

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
CONSTITUTION="$PROJECT_DIR/.specify/memory/constitution.md"

# Configuration
MAX_ITERATIONS=0  # 0 = unlimited
MODE="build"
AGY_CMD="${AGY_CMD:-agy}"
AGY_MODEL="${AGY_MODEL:-}"  # Empty = auto (let agy choose the best available model)
YOLO_FLAG="--dangerously-skip-permissions"
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
source "$SCRIPT_DIR/lib/spec_queue.sh"

# Check constitution for YOLO setting
YOLO_ENABLED=true
if [[ -f "$CONSTITUTION" ]]; then
    if grep -q "YOLO Mode.*DISABLED" "$CONSTITUTION" 2>/dev/null; then
        YOLO_ENABLED=false
    fi
fi

show_help() {
    cat <<EOF
Ralph Loop for Antigravity CLI (agy)

Based on Geoffrey Huntley's Ralph Wiggum methodology + SpecKit specs.
https://github.com/ghuntley/how-to-ralph-wiggum

Usage:
  ./scripts/ralph-loop-agy.sh                      # Build mode, unlimited iterations
  ./scripts/ralph-loop-agy.sh 20                   # Build mode, max 20 iterations
  ./scripts/ralph-loop-agy.sh plan                 # Planning mode (optional)
  ./scripts/ralph-loop-agy.sh --model "model-name" # Override model

Modes:
  build (default)  Pick spec/task and implement
  plan             Create IMPLEMENTATION_PLAN.md from specs (OPTIONAL)

Work Sources (checked in order):
  1. IMPLEMENTATION_PLAN.md - If exists, pick highest priority task
  2. specs/ folder - Otherwise, pick highest priority incomplete spec

The plan mode is OPTIONAL. Most projects can work directly from specs.

Model (default: auto — agy picks the best available model):
  Override with: AGY_MODEL=gemini-2.5-pro ./scripts/ralph-loop-agy.sh
  Or:            ./scripts/ralph-loop-agy.sh --model gemini-2.5-pro

How it works:
  1. Each iteration feeds PROMPT.md to Antigravity CLI via -p flag
  2. agy picks the HIGHEST PRIORITY incomplete spec/task
  3. agy implements, tests, and verifies acceptance criteria
  4. agy outputs <promise>DONE</promise> ONLY if criteria are met
  5. Bash loop checks for the magic phrase
  6. If found, loop continues to next iteration (fresh context)
  7. If not found, loop retries

EOF
}

print_latest_output() {
    local log_file="$1"
    local label="${2:-Antigravity}"
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
    local label="${2:-Antigravity}"
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
        --model)
            if [[ -n "${2:-}" ]]; then
                AGY_MODEL="$2"
                shift 2
            else
                echo -e "${RED}Error: --model requires a value${NC}"
                echo "Available models: run 'agy models' to see the list"
                exit 1
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

# Session log (captures ALL output)
SESSION_LOG="$LOG_DIR/ralph_agy_${MODE}_session_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$SESSION_LOG") 2>&1

# Check if Antigravity CLI is available
if ! command -v "$AGY_CMD" &> /dev/null; then
    echo -e "${RED}Error: Antigravity CLI (agy) not found${NC}"
    echo ""
    echo "Install Antigravity CLI:"
    echo "  See: https://github.com/google-deepmind/antigravity"
    echo ""
    echo "Then run 'agy' once interactively to authenticate."
    exit 1
fi

# Determine which prompt to use based on mode and available files
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="PROMPT_plan.md"
else
    PROMPT_FILE="PROMPT_build.md"
fi

# Generate minimal PROMPT files — constitution.md already contains the full workflow
cat > "PROMPT_build.md" << 'BUILDEOF'
# Ralph Loop — Build Mode

You are running inside a Ralph Wiggum autonomous loop (Context A).

Read `.specify/memory/constitution.md` — it contains all project principles, workflow
instructions, work sources, and completion signal requirements.

Find the highest-priority incomplete work item, implement it completely, verify all
acceptance criteria, commit and push, then output `<promise>DONE</promise>`.
BUILDEOF

cat > "PROMPT_plan.md" << 'PLANEOF'
# Ralph Loop — Planning Mode

You are running inside a Ralph Wiggum autonomous loop in planning mode.

Read `.specify/memory/constitution.md` for project principles.

Study `specs/` and compare against the current codebase (gap analysis).
Create or update `IMPLEMENTATION_PLAN.md` with a prioritized task breakdown.
Do NOT implement anything.

When the plan is complete, output `<promise>DONE</promise>`.
PLANEOF

# Check prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: $PROMPT_FILE not found${NC}"
    exit 1
fi

# Build Antigravity flags
# agy accepts -p "prompt" for non-interactive mode
# --model sets the model (omitted when AGY_MODEL is empty for auto-selection)
AGY_MODEL_FLAG=""
if [ -n "$AGY_MODEL" ]; then
    AGY_MODEL_FLAG="--model $AGY_MODEL"
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Check for work sources
HAS_PLAN=false
HAS_SPECS=false
SPEC_COUNT=0
INCOMPLETE_SPEC_COUNT=0
FIRST_INCOMPLETE_SPEC=""
[ -f "IMPLEMENTATION_PLAN.md" ] && HAS_PLAN=true
if [ -d "specs" ]; then
    SPEC_COUNT=$(count_root_specs "specs")
    INCOMPLETE_SPEC_COUNT=$(count_incomplete_root_specs "specs")
    [ "$SPEC_COUNT" -gt 0 ] && HAS_SPECS=true
    if [ "$INCOMPLETE_SPEC_COUNT" -gt 0 ]; then
        FIRST_INCOMPLETE_SPEC=$(get_first_incomplete_root_spec "specs")
    fi
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}           RALPH LOOP (Antigravity CLI) STARTING              ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Mode:${NC}     $MODE"
echo -e "${BLUE}Model:${NC}    ${AGY_MODEL:-auto}"
echo -e "${BLUE}Prompt:${NC}   $PROMPT_FILE"
echo -e "${BLUE}Branch:${NC}   $CURRENT_BRANCH"
echo -e "${YELLOW}YOLO:${NC}     $([ "$YOLO_ENABLED" = true ] && echo "ENABLED" || echo "DISABLED")"
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
    echo -e "  ${GREEN}✓${NC} specs/ folder ($SPEC_COUNT specs, $INCOMPLETE_SPEC_COUNT incomplete)"
    if [ "$HAS_PLAN" = false ] && [ "$INCOMPLETE_SPEC_COUNT" -gt 0 ]; then
        echo -e "    ${CYAN}Next incomplete:${NC} $FIRST_INCOMPLETE_SPEC"
    fi
else
    echo -e "  ${RED}✗${NC} specs/ folder (no .md files found)"
fi
echo ""

# Exit early if all specs are complete
if [ "$MODE" = "build" ] && [ "$HAS_PLAN" = false ] && [ "$HAS_SPECS" = true ] && [ "$INCOMPLETE_SPEC_COUNT" -eq 0 ]; then
    echo -e "${GREEN}All $SPEC_COUNT specs are COMPLETE. Nothing to do.${NC}"
    echo -e "${CYAN}To add more work, create a new spec in specs/ without 'Status: COMPLETE'.${NC}"
    exit 0
fi

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
    LOG_FILE="$LOG_DIR/ralph_agy_${MODE}_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').log"
    : > "$LOG_FILE"
    WATCH_PID=""

    if [ "$ROLLING_OUTPUT_INTERVAL" -gt 0 ] && [ "$ROLLING_OUTPUT_LINES" -gt 0 ] && [ -t 1 ] && [ -w /dev/tty ]; then
        watch_latest_output "$LOG_FILE" "Antigravity" &
        WATCH_PID=$!
    fi

    # Run Antigravity CLI with prompt passed via -p flag
    # -p "prompt" runs non-interactively
    # --dangerously-skip-permissions auto-approves all tool calls
    # --model sets the model (omitted for auto-selection)
    AGY_OUTPUT=""
    if AGY_OUTPUT=$("$AGY_CMD" -p "$(cat "$PROMPT_FILE")" $AGY_MODEL_FLAG $([ "$YOLO_ENABLED" = true ] && echo "$YOLO_FLAG") 2>&1 | tee "$LOG_FILE"); then
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo ""
        echo -e "${GREEN}✓ Antigravity execution completed${NC}"

        # Check if DONE promise was output (accept both DONE and ALL_DONE variants)
        if echo "$AGY_OUTPUT" | grep -qE "<promise>(ALL_)?DONE</promise>"; then
            DETECTED_SIGNAL=$(echo "$AGY_OUTPUT" | grep -oE "<promise>(ALL_)?DONE</promise>" | tail -1)
            echo -e "${GREEN}✓ Completion signal detected: ${DETECTED_SIGNAL}${NC}"
            echo -e "${GREEN}✓ Task completed successfully!${NC}"
            CONSECUTIVE_FAILURES=0

            # Break if ALL_DONE
            if [ "$DETECTED_SIGNAL" = "<promise>ALL_DONE</promise>" ]; then
                echo ""
                echo -e "${GREEN}All work is done! Exiting loop.${NC}"
                break
            fi

            # For planning mode, stop after one successful plan
            if [ "$MODE" = "plan" ]; then
                echo ""
                echo -e "${GREEN}Planning complete!${NC}"
                echo -e "${CYAN}Run './scripts/ralph-loop-agy.sh' to start building.${NC}"
                echo -e "${CYAN}Or delete IMPLEMENTATION_PLAN.md to work directly from specs.${NC}"
                break
            fi
        else
            echo -e "${YELLOW}⚠ No completion signal found${NC}"
            echo -e "${YELLOW}  Agent did not output <promise>DONE</promise> or <promise>ALL_DONE</promise>${NC}"
            echo -e "${YELLOW}  This means acceptance criteria were not met.${NC}"
            echo -e "${YELLOW}  Retrying in next iteration...${NC}"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            print_latest_output "$LOG_FILE" "Antigravity"

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
        echo -e "${RED}✗ Antigravity execution failed${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        print_latest_output "$LOG_FILE" "Antigravity"
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
echo -e "${GREEN}   RALPH LOOP (Antigravity) FINISHED ($ITERATION iterations)   ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
