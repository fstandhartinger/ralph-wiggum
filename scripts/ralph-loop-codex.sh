#!/bin/bash
#
# Ralph Loop for OpenAI Codex CLI
#
# Based on Geoffrey Huntley's Ralph Wiggum methodology.
# Combined with SpecKit-style specifications.
#
# Usage:
#   ./scripts/ralph-loop-codex.sh              # Build mode (unlimited)
#   ./scripts/ralph-loop-codex.sh 20           # Build mode (max 20 iterations)
#   ./scripts/ralph-loop-codex.sh plan         # Planning mode (optional)
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
RLM_CONTEXT_FILE=""
CODEX_CMD="${CODEX_CMD:-codex}"
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
Ralph Loop for OpenAI Codex CLI

Usage:
  ./scripts/ralph-loop-codex.sh              # Build mode, unlimited
  ./scripts/ralph-loop-codex.sh 20           # Build mode, max 20 iterations
  ./scripts/ralph-loop-codex.sh plan         # Planning mode (OPTIONAL)
  ./scripts/ralph-loop-codex.sh --rlm-context ./rlm/context.txt
  ./scripts/ralph-loop-codex.sh --rlm ./rlm/context.txt

Modes:
  build (default)  Pick incomplete spec and implement
  plan             Create IMPLEMENTATION_PLAN.md (OPTIONAL)

Work Source:
  Agent reads specs/*.md and picks the highest priority incomplete spec.

YOLO Mode: Uses --dangerously-bypass-approvals-and-sandbox

RLM Mode (optional):
  --rlm-context <file>  Treat a large context file as external environment.
                        The agent should read slices instead of loading it all.
  --rlm [file]          Shortcut for --rlm-context (defaults to rlm/context.txt)

RLM workspace (when enabled):
  - rlm/trace/     Prompt snapshots + outputs per iteration
  - rlm/index.tsv  Index of all iterations (timestamp, prompt, log, status)
  - rlm/queries/ and rlm/answers/  For optional recursive sub-queries

EOF
}

print_latest_output() {
    local log_file="$1"
    local label="${2:-Codex}"
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
    local label="${2:-Codex}"
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
SESSION_LOG="$LOG_DIR/ralph_codex_${MODE}_session_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$SESSION_LOG") 2>&1

# Check if Codex CLI is available
if ! command -v "$CODEX_CMD" &> /dev/null; then
    echo -e "${RED}Error: Codex CLI not found${NC}"
    echo ""
    echo "Install Codex CLI:"
    echo "  npm install -g @openai/codex"
    echo ""
    echo "Then authenticate:"
    echo "  codex login"
    exit 1
fi

# Determine prompt file
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="PROMPT_plan.md"
else
    PROMPT_FILE="PROMPT_build.md"
fi

# Check prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: $PROMPT_FILE not found${NC}"
    echo "Create the prompt file or run ./scripts/ralph-loop.sh first."
    exit 1
fi

# Build Codex flags for exec mode
CODEX_FLAGS="exec"
if [ "$YOLO_ENABLED" = true ]; then
    CODEX_FLAGS="$CODEX_FLAGS --dangerously-bypass-approvals-and-sandbox"
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Check for work sources - count .md files in specs/
HAS_SPECS=false
SPEC_COUNT=0
if [ -d "specs" ]; then
    SPEC_COUNT=$(find specs -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l)
    [ "$SPEC_COUNT" -gt 0 ] && HAS_SPECS=true
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}              RALPH LOOP (Codex) STARTING                    ${NC}"
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
if [ "$HAS_SPECS" = true ]; then
    echo -e "  ${GREEN}✓${NC} specs/ folder ($SPEC_COUNT specs)"
else
    echo -e "  ${RED}✗${NC} specs/ folder (no .md files found)"
fi
echo ""
echo -e "${CYAN}Using: $CODEX_CMD $CODEX_FLAGS${NC}"
echo -e "${CYAN}Agent must output <promise>DONE</promise> when complete.${NC}"
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
    LOG_FILE="$LOG_DIR/ralph_codex_${MODE}_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').log"
    OUTPUT_FILE="$LOG_DIR/ralph_codex_output_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').txt"
    RLM_STATUS="unknown"
    : > "$LOG_FILE"
    WATCH_PID=""

    if [ "$ROLLING_OUTPUT_INTERVAL" -gt 0 ] && [ "$ROLLING_OUTPUT_LINES" -gt 0 ] && [ -t 1 ] && [ -w /dev/tty ]; then
        watch_latest_output "$LOG_FILE" "Codex" &
        WATCH_PID=$!
    fi

    # Optional RLM context block appended to prompt at runtime
    EFFECTIVE_PROMPT_FILE="$PROMPT_FILE"
    if [ -n "$RLM_CONTEXT_FILE" ]; then
        EFFECTIVE_PROMPT_FILE="$LOG_DIR/ralph_codex_prompt_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').md"
        cat "$PROMPT_FILE" > "$EFFECTIVE_PROMPT_FILE"
        cat >> "$EFFECTIVE_PROMPT_FILE" << EOF

---
## RLM Context (Optional)

You have access to a large context file at:
**$RLM_CONTEXT_FILE**

Treat this file as an external environment. Do NOT paste the whole file into the prompt.
Instead, inspect it programmatically and recursively:

- Use small slices:
  \`\`\`bash
  sed -n 'START,ENDp' "$RLM_CONTEXT_FILE"
  \`\`\`
- Or Python snippets:
  \`\`\`bash
  python - <<'PY'
  from pathlib import Path
  p = Path("$RLM_CONTEXT_FILE")
  print(p.read_text().splitlines()[START:END])
  PY
  \`\`\`
- Use search:
  \`\`\`bash
  rg -n "pattern" "$RLM_CONTEXT_FILE"
  \`\`\`

Goal: decompose the task into smaller sub-queries and only load the pieces you need.
This mirrors the Recursive Language Model approach from https://arxiv.org/html/2512.24601v1

## RLM Workspace (Optional)

Past loop outputs are preserved on disk:
- Iteration logs: \`logs/\`
- Prompt/output snapshots: \`rlm/trace/\`
- Iteration index: \`rlm/index.tsv\`

Use these as an external memory store (search/slice as needed).
If you need a recursive sub-query, write a focused prompt in \`rlm/queries/\`,
run:
  \`./scripts/rlm-subcall.sh --query rlm/queries/<file>.md\`
and store the result in \`rlm/answers/\`.
EOF
        RLM_PROMPT_SNAPSHOT="$RLM_TRACE_DIR/iter_${ITERATION}_prompt.md"
        cp "$EFFECTIVE_PROMPT_FILE" "$RLM_PROMPT_SNAPSHOT"
    fi

    # Run Codex with exec mode, reading prompt from stdin with "-"
    # Use --output-last-message to capture the final response for checking
    echo -e "${BLUE}Running: cat $EFFECTIVE_PROMPT_FILE | $CODEX_CMD $CODEX_FLAGS - --output-last-message $OUTPUT_FILE${NC}"
    echo ""
    
    CODEX_EXIT=0
    if cat "$EFFECTIVE_PROMPT_FILE" | "$CODEX_CMD" $CODEX_FLAGS - --output-last-message "$OUTPUT_FILE" 2>&1 | tee "$LOG_FILE"; then
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo ""
        echo -e "${GREEN}✓ Codex execution completed${NC}"
        
        # Check if DONE promise was output (in the last message file)
        if [ -f "$OUTPUT_FILE" ] && grep -q "<promise>DONE</promise>" "$OUTPUT_FILE"; then
            echo -e "${GREEN}✓ Completion signal detected: <promise>DONE</promise>${NC}"
            echo -e "${GREEN}✓ Task completed successfully!${NC}"
            CONSECUTIVE_FAILURES=0
            RLM_STATUS="done"
            
            if [ "$MODE" = "plan" ]; then
                echo ""
                echo -e "${GREEN}Planning complete!${NC}"
                break
            fi
        # Also check the main log
        elif grep -q "<promise>DONE</promise>" "$LOG_FILE"; then
            echo -e "${GREEN}✓ Completion signal detected in output${NC}"
            echo -e "${GREEN}✓ Task completed successfully!${NC}"
            CONSECUTIVE_FAILURES=0
            RLM_STATUS="done"
        else
            echo -e "${YELLOW}⚠ No completion signal found${NC}"
            echo -e "${YELLOW}  Agent did not output <promise>DONE</promise>${NC}"
            echo -e "${YELLOW}  Retrying in next iteration...${NC}"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            RLM_STATUS="incomplete"
            print_latest_output "$LOG_FILE" "Codex"
            
            if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
                echo ""
                echo -e "${RED}⚠ $MAX_CONSECUTIVE_FAILURES consecutive iterations without completion.${NC}"
                echo -e "${RED}  The agent may be stuck. Check logs:${NC}"
                echo -e "${RED}  - $LOG_FILE${NC}"
                echo -e "${RED}  - $OUTPUT_FILE${NC}"
                CONSECUTIVE_FAILURES=0
            fi
        fi
    else
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        CODEX_EXIT=$?
        echo -e "${RED}✗ Codex execution failed (exit code: $CODEX_EXIT)${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        RLM_STATUS="error"
        print_latest_output "$LOG_FILE" "Codex"
    fi

    # Record iteration in RLM index (optional)
    if [ -n "$RLM_CONTEXT_FILE" ]; then
        RLM_PROMPT_PATH="${RLM_PROMPT_SNAPSHOT:-}"
        RLM_OUTPUT_SNAPSHOT="$RLM_TRACE_DIR/iter_${ITERATION}_output.log"
        cp "$LOG_FILE" "$RLM_OUTPUT_SNAPSHOT"
        if [ -f "$OUTPUT_FILE" ]; then
            RLM_LAST_MESSAGE_SNAPSHOT="$RLM_TRACE_DIR/iter_${ITERATION}_last_message.txt"
            cp "$OUTPUT_FILE" "$RLM_LAST_MESSAGE_SNAPSHOT"
        fi
        RLM_OUTPUT_PATH="${RLM_LAST_MESSAGE_SNAPSHOT:-$RLM_OUTPUT_SNAPSHOT}"
        echo -e "${TIMESTAMP}\t${MODE}\t${ITERATION}\t${RLM_PROMPT_PATH}\t${LOG_FILE}\t${RLM_OUTPUT_PATH}\t${RLM_STATUS}" >> "$RLM_INDEX"
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" 2>/dev/null || {
        if git log origin/$CURRENT_BRANCH..HEAD --oneline 2>/dev/null | grep -q .; then
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
echo -e "${GREEN}       RALPH LOOP (Codex) FINISHED ($ITERATION iterations)   ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
