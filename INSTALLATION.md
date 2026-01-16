# AI AGENT: Execute These Instructions

> **YOU ARE AN AI CODING AGENT.** Follow these instructions to set up Ralph Wiggum in the user's project.
>
> **DO NOT just describe these steps.** Actually execute them using your file creation tools.

---

## Phase 1: Create Directory Structure

Create these directories in the user's project:

```bash
mkdir -p specs
mkdir -p scripts
mkdir -p logs
```

---

## Phase 2: Copy Core Files

Copy the following files from this repository's `templates/` folder to the user's project root:

1. `templates/PROMPT_build.md` → `PROMPT_build.md`
2. `templates/PROMPT_plan.md` → `PROMPT_plan.md`
3. `templates/AGENTS.md` → `AGENTS.md`
4. `templates/IMPLEMENTATION_PLAN.md` → `IMPLEMENTATION_PLAN.md`

Copy the loop scripts:

1. `scripts/ralph-loop.sh` → `scripts/ralph-loop.sh`
2. `scripts/ralph-loop-codex.sh` → `scripts/ralph-loop-codex.sh`

Make scripts executable:

```bash
chmod +x scripts/ralph-loop.sh scripts/ralph-loop-codex.sh
```

---

## Phase 3: Customize for Project

Ask the user these questions to customize the setup:

### Question 1: Project Name
> "What is the name of your project?"

### Question 2: Build Commands
> "What commands are used to build/run your project? (e.g., npm install, npm run dev)"

### Question 3: Test Commands
> "What commands are used to test your project? (e.g., npm test, npm run lint)"

### Question 4: Project Structure
> "Where is your main source code located? (e.g., src/, app/, lib/)"

Use the answers to update `AGENTS.md` with the correct:
- Build & Run commands
- Validation commands
- Project structure description

---

## Phase 4: Explain the Workflow

Tell the user:

---

### ✅ Ralph Wiggum is Ready!

Based on [Geoffrey Huntley's methodology](https://github.com/ghuntley/how-to-ralph-wiggum), your project is now set up with:

**Files created:**
- `PROMPT_build.md` — Instructions for build iterations
- `PROMPT_plan.md` — Instructions for planning iterations
- `AGENTS.md` — Operational guide (how to build/test)
- `IMPLEMENTATION_PLAN.md` — Shared state between loops
- `scripts/ralph-loop.sh` — Claude Code loop script
- `scripts/ralph-loop-codex.sh` — OpenAI Codex loop script

**How it works:**
1. Each iteration feeds `PROMPT.md` to the AI agent via stdin
2. Agent reads `IMPLEMENTATION_PLAN.md` to pick the next task
3. Agent implements, tests, and commits
4. Loop restarts with fresh context
5. Agent reads updated plan, picks next task

**Two modes:**
- **Plan mode**: Creates task list from specs → `./scripts/ralph-loop.sh plan`
- **Build mode**: Implements from plan → `./scripts/ralph-loop.sh`

---

### Next Steps

1. **Create your specifications** in `specs/` folder:
   ```
   specs/
   └── 001-my-feature/
       └── spec.md
   ```

2. **Run planning mode** to analyze specs and create the task list:
   ```bash
   ./scripts/ralph-loop.sh plan
   ```

3. **Run build mode** to implement:
   ```bash
   ./scripts/ralph-loop.sh        # Unlimited iterations
   ./scripts/ralph-loop.sh 20     # Max 20 iterations
   ```

4. **Watch and observe** — Ralph may need guidance at first. Adjust prompts as patterns emerge.

---

### The Magic Words

When you're ready to start Ralph:

**Claude Code:**
```bash
./scripts/ralph-loop.sh
```

**OpenAI Codex:**
```bash
./scripts/ralph-loop-codex.sh
```

**Stop anytime:** Press `Ctrl+C`

---

## Files Reference

```
project-root/
├── scripts/
│   ├── ralph-loop.sh            # Claude Code loop
│   └── ralph-loop-codex.sh      # OpenAI Codex loop
├── PROMPT_build.md              # Build mode instructions
├── PROMPT_plan.md               # Planning mode instructions
├── IMPLEMENTATION_PLAN.md       # Shared state (task list)
├── AGENTS.md                    # Operational guide
├── logs/                        # Iteration logs
└── specs/                       # Your specifications
    └── NNN-feature-name/
        └── spec.md
```

---

## YOLO Mode

Both scripts run in YOLO mode by default:
- Claude: `--dangerously-skip-permissions`
- Codex: `--dangerously-bypass-approvals-and-sandbox`

This bypasses permission prompts for fully autonomous operation. Use in a sandboxed environment for safety.
