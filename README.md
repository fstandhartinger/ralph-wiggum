# 🧠 Ralph Wiggum

> Autonomous AI coding with spec-driven development

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Quick Start

**AI Agent? Start Here:**
> Read and execute [INSTALLATION.md](INSTALLATION.md) for a guided setup.

**Human Developer? Start Here:**
> Read [INSTALL.md](INSTALL.md) for manual setup instructions.

---

## What is Ralph Wiggum?

Ralph Wiggum is an approach to **fully autonomous AI-assisted software development** that combines:

- 🔄 **Iterative self-correction** — Each iteration picks ONE task from the plan, implements it, and commits
- 📋 **Spec-driven development** — Professional-grade specifications guide the work
- 🎯 **Fresh context each loop** — Every iteration starts with a clean context window
- 📝 **Shared state via files** — `IMPLEMENTATION_PLAN.md` persists between loops
- ⚡ **Backpressure via tests** — Tests/builds reject invalid work

---

## How It Works

Based on [Geoffrey Huntley's Ralph Wiggum methodology](https://github.com/ghuntley/how-to-ralph-wiggum):

```
┌─────────────────────────────────────────────────────────────┐
│                     RALPH LOOP                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Orient    │───▶│   Pick Task  │───▶│  Implement   │  │
│  │  Read specs  │    │  from Plan   │    │   & Test     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                   │         │
│         ┌────────────────────────────────────────┘         │
│         ▼                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Commit    │───▶│ Update Plan  │───▶│ Fresh Start  │  │
│  │   & Push     │    │   on Disk    │    │ (Loop Again) │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Two Modes, Same Loop

| Mode | Purpose | Prompt File |
|------|---------|-------------|
| **plan** | Gap analysis: compare specs vs code, create prioritized task list | `PROMPT_plan.md` |
| **build** | Implementation: pick task, implement, test, commit | `PROMPT_build.md` |

---

## Usage

```bash
# Planning mode - creates/updates IMPLEMENTATION_PLAN.md
./scripts/ralph-loop.sh plan

# Build mode - implements from plan
./scripts/ralph-loop.sh          # Unlimited iterations
./scripts/ralph-loop.sh 20       # Max 20 iterations

# Using Codex instead of Claude
./scripts/ralph-loop-codex.sh plan
./scripts/ralph-loop-codex.sh 20
```

### Key Files

```
project-root/
├── scripts/
│   ├── ralph-loop.sh            # Claude Code loop
│   └── ralph-loop-codex.sh      # OpenAI Codex loop
├── PROMPT_build.md              # Build mode instructions
├── PROMPT_plan.md               # Planning mode instructions
├── IMPLEMENTATION_PLAN.md       # Shared state (task list)
├── AGENTS.md                    # Operational guide
└── specs/                       # Requirement specifications
    └── NNN-feature-name/
        └── spec.md
```

---

## Core Principles

### 1. Context Is Everything
- Each iteration gets a fresh context window
- Agent reads the same files every time: `PROMPT.md` + `AGENTS.md`
- `IMPLEMENTATION_PLAN.md` is the shared state on disk

### 2. One Task Per Loop
- Each iteration selects ONE task from the plan
- Implements it completely
- Commits and pushes
- Exits (context garbage collected)

### 3. Backpressure via Tests
- Tests, lints, builds reject invalid work
- Agent must fix issues before committing
- Natural convergence through iteration

### 4. Let Ralph Ralph
- Trust the AI to self-identify, self-correct, and self-improve
- Don't micromanage task selection
- Observe patterns and adjust prompts/guardrails

---

## Supported Platforms

| Platform | Script | YOLO Flag |
|----------|--------|-----------|
| Claude Code | `ralph-loop.sh` | `--dangerously-skip-permissions` |
| OpenAI Codex | `ralph-loop-codex.sh` | `--dangerously-bypass-approvals-and-sandbox` |
| Cursor | Interactive (use `/speckit.implement`) | N/A |

---

## Getting Started

1. **Clone this template** or copy the files to your project
2. **Create your specs** in `specs/` folder
3. **Run planning mode** to create the task list: `./scripts/ralph-loop.sh plan`
4. **Run build mode** to implement: `./scripts/ralph-loop.sh`
5. **Watch and observe** — adjust prompts as patterns emerge

---

## Credits

This approach builds upon and is inspired by:

- [Geoffrey Huntley's how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) — The original comprehensive guide
- [Original Ralph Wiggum technique](https://awesomeclaude.ai/ralph-wiggum) — By the Claude community
- [Claude Code Ralph Wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [SpecKit](https://github.com/github/spec-kit) by GitHub — Spec-driven development

Our contribution is simplifying the setup and providing a ready-to-use template that integrates these approaches.

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

**Website**: [ralph-wiggum-web.onrender.com](https://ralph-wiggum-web.onrender.com)
