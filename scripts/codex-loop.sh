#!/bin/bash
#
# Codex Loop - Ralph Wiggum for OpenAI Codex CLI
#
# This script runs the Ralph Wiggum loop using OpenAI Codex CLI.
# Inspired by: https://github.com/frankbria/ralph-claude-code/blob/main/ralph_loop.sh
#
# Usage:
#   ./scripts/codex-loop.sh "Your prompt here"
#   ./scripts/codex-loop.sh --prompt-file PROMPT.md
#   ./scripts/codex-loop.sh --spec 001-project-setup
#   ./scripts/codex-loop.sh --all
#
# Requirements:
#   - OpenAI Codex CLI: npm install -g @openai/codex
#   - Authenticated: codex --login
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
PROMPT_FILE=""
PROMPT_TEXT=""
SPEC_NAME=""
ALL_SPECS=false
FULL_AUTO=false
QUIET=false
MAX_ITERATIONS=30
# Use absolute path for logs based on where script is run from
WORK_DIR="$(pwd)"
LOG_DIR="$WORK_DIR/logs"
STATUS_FILE="$WORK_DIR/.codex-status.json"

# Create log directory
mkdir -p "$LOG_DIR"

log_status() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case $level in
        "INFO")  color=$BLUE ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "LOOP") color=$PURPLE ;;
    esac
    
    echo -e "${color}[$timestamp] [$level] $message${NC}"
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/codex-loop.log"
}

update_status() {
    local status=$1
    local message=$2
    
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "status": "$status",
    "message": "$message",
    "spec": "$SPEC_NAME",
    "all_specs": $ALL_SPECS
}
EOF
}

show_help() {
    cat << EOF
Codex Loop - Ralph Wiggum for OpenAI Codex CLI

Usage:
    $0 "Your prompt here"           Run with inline prompt
    $0 --prompt-file PROMPT.md      Run with prompt from file
    $0 --spec 001-project-setup     Run for specific spec
    $0 --all                        Run for all specs

Options:
    -h, --help              Show this help message
    -p, --prompt-file FILE  Read prompt from file
    -s, --spec NAME         Run for a specific spec in specs/ folder
    -a, --all               Run for all specs in order
    -f, --full-auto         Run in full-auto mode (no confirmations)
    -q, --quiet             Suppress output except errors
    --max-iterations NUM    Maximum iterations (default: 30)

Examples:
    $0 "Implement the user authentication feature"
    $0 --prompt-file PROMPT.md --full-auto
    $0 --spec 001-project-setup
    $0 --all --full-auto --quiet

Prerequisites:
    1. Install Codex CLI:     npm install -g @openai/codex
    2. Authenticate:          codex --login
    
For more information: https://github.com/fstandhartinger/ralph-wiggum
EOF
}

check_codex_installed() {
    if ! command -v codex &> /dev/null; then
        log_status "ERROR" "Codex CLI not found!"
        echo ""
        echo "Install Codex CLI:"
        echo "  npm install -g @openai/codex"
        echo ""
        echo "Then authenticate:"
        echo "  codex --login"
        exit 1
    fi
    log_status "SUCCESS" "Codex CLI found: $(which codex)"
}

# Build prompt for a single spec
build_spec_prompt() {
    local spec="$1"
    cat <<EOF
Implement the spec '$spec' from specs/$spec/spec.md.

BEFORE YOU START, read these files in order:
1. RALPH_PROMPT.md (if exists) - Master instructions
2. .specify/memory/constitution.md - Core principles  
3. AGENTS.md - Development guidelines

PROCESS:
1. Read the spec file thoroughly
2. Implement the feature following ALL acceptance criteria
3. Run tests as required by the Completion Signal section
4. Use browser automation to verify UI if applicable
5. Commit and push with meaningful messages
6. Iterate until ALL checks pass

AUTONOMY: You have FULL autonomy. Commit, push, deploy without asking permission.

COMPLETION: Output <promise>DONE</promise> when ALL acceptance criteria pass.
EOF
}

# Build prompt for all specs
build_all_specs_prompt() {
    cat <<EOF
Implement ALL specifications in the specs/ folder, one by one, in numerical order.

BEFORE YOU START, read these files in order:
1. RALPH_PROMPT.md (if exists) - Master instructions
2. .specify/memory/constitution.md - Core principles
3. AGENTS.md - Development guidelines
4. history.md (if exists) - See what's already been done

PROCESS for EACH spec:
1. Read specs/{spec-name}/spec.md
2. Implement following ALL acceptance criteria
3. Run tests as required by the Completion Signal
4. Commit and push with meaningful messages
5. Move to the next spec only after current one is DONE

AUTONOMY: You have FULL autonomy. Commit, push, deploy without asking permission.

COMPLETION: Output <promise>ALL_DONE</promise> when ALL specs are complete.
EOF
}

run_codex() {
    local prompt="$1"
    local args=""
    
    if [[ "$FULL_AUTO" == "true" ]]; then
        args="$args --full-auto"
    fi
    
    if [[ "$QUIET" == "true" ]]; then
        args="$args --quiet"
    fi
    
    log_status "LOOP" "Starting Codex with prompt..."
    log_status "INFO" "Mode: $([ "$FULL_AUTO" == "true" ] && echo "full-auto" || echo "interactive")"
    
    update_status "running" "Codex loop started"
    
    # Run codex with the prompt
    if [[ -n "$args" ]]; then
        log_status "INFO" "Running: codex $args \"<prompt>\""
        codex $args "$prompt"
    else
        log_status "INFO" "Running: codex \"<prompt>\""
        codex "$prompt"
    fi
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_status "SUCCESS" "Codex completed successfully"
        update_status "completed" "Codex loop finished"
    else
        log_status "ERROR" "Codex exited with code $exit_code"
        update_status "error" "Codex exited with code $exit_code"
    fi
    
    return $exit_code
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--prompt-file)
            PROMPT_FILE="$2"
            shift 2
            ;;
        -s|--spec)
            SPEC_NAME="$2"
            shift 2
            ;;
        -a|--all)
            ALL_SPECS=true
            shift
            ;;
        -f|--full-auto)
            FULL_AUTO=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        *)
            # If no flag, treat as inline prompt
            if [[ -z "$PROMPT_TEXT" ]]; then
                PROMPT_TEXT="$1"
            fi
            shift
            ;;
    esac
done

# Main execution
cd "$PROJECT_DIR"

log_status "INFO" "Ralph Wiggum Codex Loop"
log_status "INFO" "Working directory: $(pwd)"

check_codex_installed

# Determine prompt source
PROMPT=""

if [[ "$ALL_SPECS" == "true" ]]; then
    log_status "INFO" "Mode: All specs"
    PROMPT=$(build_all_specs_prompt)
elif [[ -n "$SPEC_NAME" ]]; then
    if [[ ! -d "specs/$SPEC_NAME" ]]; then
        log_status "ERROR" "Spec '$SPEC_NAME' not found in specs/ folder"
        echo "Available specs:"
        ls -1 specs/ 2>/dev/null || echo "  (no specs folder found)"
        exit 1
    fi
    log_status "INFO" "Mode: Single spec - $SPEC_NAME"
    PROMPT=$(build_spec_prompt "$SPEC_NAME")
elif [[ -n "$PROMPT_FILE" ]]; then
    if [[ ! -f "$PROMPT_FILE" ]]; then
        log_status "ERROR" "Prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    log_status "INFO" "Mode: Prompt file - $PROMPT_FILE"
    PROMPT=$(cat "$PROMPT_FILE")
elif [[ -n "$PROMPT_TEXT" ]]; then
    log_status "INFO" "Mode: Inline prompt"
    PROMPT="$PROMPT_TEXT"
else
    log_status "ERROR" "No prompt specified!"
    echo ""
    show_help
    exit 1
fi

echo ""
log_status "LOOP" "=========================================="
log_status "LOOP" "Starting Ralph Wiggum Codex Loop"
log_status "LOOP" "=========================================="
echo ""

run_codex "$PROMPT"

echo ""
log_status "SUCCESS" "Ralph Wiggum Codex Loop completed!"
