#!/bin/bash
#
# Ralph Loop for OpenAI Codex CLI
#
# Based on Geoffrey Huntley's Ralph Wiggum methodology:
# https://github.com/ghuntley/how-to-ralph-wiggum
#
# Uses --dangerously-bypass-approvals-and-sandbox for YOLO mode.
#
# Usage:
#   ./scripts/ralph-loop-codex.sh              # Build mode (unlimited)
#   ./scripts/ralph-loop-codex.sh 20           # Build mode (max 20 iterations)
#   ./scripts/ralph-loop-codex.sh plan         # Planning mode
#   ./scripts/ralph-loop-codex.sh plan 5       # Planning mode (max 5 iterations)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"

# Configuration
MAX_ITERATIONS=0  # 0 = unlimited
MODE="build"
CODEX_CMD="codex"
CODEX_YOLO_FLAG="--dangerously-bypass-approvals-and-sandbox"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

show_help() {
    cat <<EOF
Ralph Loop for OpenAI Codex CLI

Based on Geoffrey Huntley's Ralph Wiggum methodology.
https://github.com/ghuntley/how-to-ralph-wiggum

Usage:
  ./scripts/ralph-loop-codex.sh              # Build mode, unlimited iterations
  ./scripts/ralph-loop-codex.sh 20           # Build mode, max 20 iterations
  ./scripts/ralph-loop-codex.sh plan         # Planning mode, unlimited
  ./scripts/ralph-loop-codex.sh plan 5       # Planning mode, max 5 iterations

Modes:
  build (default)  Implements tasks from IMPLEMENTATION_PLAN.md
  plan             Creates/updates IMPLEMENTATION_PLAN.md from specs

YOLO Mode: Uses $CODEX_YOLO_FLAG

How it works:
  1. Each iteration feeds PROMPT.md to Codex
  2. Codex picks the most important task from the plan
  3. Codex implements, tests, commits
  4. Loop restarts with fresh context
  5. Continues until max iterations or manual stop (Ctrl+C)

Prerequisites:
  - OpenAI Codex CLI: npm install -g @openai/codex
  - Authenticated: codex --login

EOF
}

# Parse arguments
if [ "$1" = "plan" ]; then
    MODE="plan"
    MAX_ITERATIONS=${2:-0}
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    MODE="build"
    MAX_ITERATIONS=$1
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

cd "$PROJECT_DIR"

# Determine prompt file
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="PROMPT_plan.md"
else
    PROMPT_FILE="PROMPT_build.md"
fi

# Check if Codex CLI is available
if ! command -v "$CODEX_CMD" &> /dev/null; then
    echo -e "${RED}Error: Codex CLI not found${NC}"
    echo ""
    echo "Install Codex CLI:"
    echo "  npm install -g @openai/codex"
    echo ""
    echo "Then authenticate:"
    echo "  codex --login"
    exit 1
fi

# Check prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: $PROMPT_FILE not found${NC}"
    echo ""
    echo "Create prompt files first. See templates/ for examples."
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}              RALPH LOOP (CODEX) STARTING                    ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Mode:${NC}    $MODE"
echo -e "${BLUE}Prompt:${NC}  $PROMPT_FILE"
echo -e "${BLUE}Branch:${NC}  $CURRENT_BRANCH"
echo -e "${YELLOW}YOLO:${NC}    ENABLED ($CODEX_YOLO_FLAG)"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${BLUE}Max:${NC}     $MAX_ITERATIONS iterations"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the loop${NC}"
echo ""

ITERATION=0

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
    LOG_FILE="$LOG_DIR/ralph_codex_${MODE}_$(date '+%Y%m%d_%H%M%S').log"

    # Read prompt and run Codex
    PROMPT_CONTENT=$(cat "$PROMPT_FILE")
    
    if "$CODEX_CMD" $CODEX_YOLO_FLAG "$PROMPT_CONTENT" 2>&1 | tee "$LOG_FILE"; then
        echo ""
        echo -e "${GREEN}✓ Iteration $ITERATION completed${NC}"
        
        # Check if DONE promise was output
        if grep -q "<promise>DONE</promise>" "$LOG_FILE" 2>/dev/null; then
            echo -e "${GREEN}✓ Completion signal detected${NC}"
        else
            echo -e "${YELLOW}No completion signal - will retry...${NC}"
        fi
    else
        echo -e "${RED}✗ Iteration $ITERATION failed${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" 2>/dev/null || {
        echo -e "${YELLOW}Push failed, creating remote branch...${NC}"
        git push -u origin "$CURRENT_BRANCH" 2>/dev/null || true
    }

    # Brief pause between iterations
    echo ""
    echo -e "${BLUE}Waiting 3s before next iteration...${NC}"
    sleep 3
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}      RALPH LOOP (CODEX) FINISHED ($ITERATION iterations)    ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
