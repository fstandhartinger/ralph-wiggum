# AI Agent: Ralph Wiggum Setup

> **You're an AI coding agent.** Follow these instructions to set up Ralph Wiggum.
>
> **Actually execute these steps** — don't just describe them.

---

## Overview: What You'll Do

1. **Quick Setup** — Create directories and download scripts (1 minute)
2. **Project Interview** — Learn about the user's project vision (3-5 minutes)
3. **Constitution** — Create the project's guiding document
4. **Next Steps** — Explain how to create specs and start Ralph

The goal: Make this feel **lightweight, pleasant, and professional**. Focus on understanding the *project*, not interrogating about technical minutiae.

---

## Phase 1: Create Structure

```bash
mkdir -p .specify/memory specs scripts logs history .cursor/commands .claude/commands
```

---

## Phase 2: Download Scripts

Fetch from GitHub raw URLs:

| Script | URL | Save To |
|--------|-----|---------|
| ralph-loop.sh | `https://raw.githubusercontent.com/fstandhartinger/ralph-wiggum/main/scripts/ralph-loop.sh` | `scripts/ralph-loop.sh` |
| ralph-loop-codex.sh | `https://raw.githubusercontent.com/fstandhartinger/ralph-wiggum/main/scripts/ralph-loop-codex.sh` | `scripts/ralph-loop-codex.sh` |

```bash
chmod +x scripts/ralph-loop.sh scripts/ralph-loop-codex.sh
```

---

## Phase 3: Get Version Info

```bash
git ls-remote https://github.com/fstandhartinger/ralph-wiggum.git HEAD | cut -f1
```

Store the commit hash for the constitution.

---

## Phase 4: Project Interview

### Introduction

Start with a warm, brief introduction:

> "I'll ask a few quick questions to understand your project. This creates a **constitution** — a short document that helps me stay aligned with your goals across all future sessions.
>
> Don't worry about getting everything perfect — we can always refine it later."

### The Questions

Present these conversationally, one at a time. **Keep it lightweight.**

---

#### 1. Project Name
> "What's the name of your project?"

---

#### 2. Project Vision (MOST IMPORTANT)

> "Tell me about your project — what is it, what problem does it solve, who is it for?
>
> This is the most important question. The more I understand your vision, the better I can help build it."

**Note to AI:** This is the heart of the interview. Encourage the user to share context. A few sentences to a paragraph is ideal. This understanding guides everything.

---

#### 3. Core Principles

> "What 2-3 principles should guide development? Think about what matters most.
>
> Examples: 'User experience first', 'Keep it simple', 'Security above all', 'Move fast', 'Quality over speed'"

**Note to AI:** If the user struggles, offer to suggest principles based on their project description.

---

#### 4. Technical Stack (OPTIONAL)

> "What's the tech stack? (Or should I figure it out from the codebase?)
>
> For existing projects, I can usually detect this automatically. For new projects, I can suggest a stack based on your requirements."

**Note to AI:** This is **optional**. For existing projects, you should analyze the codebase yourself (check package.json, requirements.txt, go.mod, Cargo.toml, etc.). For new projects, you can recommend a stack. Don't pressure the user to specify every detail.

---

#### 5. Autonomy Settings

Present these together as a quick setup:

> "Two quick settings for how Ralph operates:
>
> **YOLO Mode** (recommended for smooth operation):
> Allows me to execute commands, modify files, and run tests without asking permission each time. This is what makes the autonomous loop work smoothly.
>
> **Git Autonomy** (recommended):
> Allows me to commit and push changes automatically after completing each spec.
>
> Enable both? (yes/no) — You can change these anytime."

**Note to AI:** Default to YES for both if the user seems agreeable. The loop works poorly without these.

---

### Interview Complete

Thank the user briefly and move on:

> "That's all I need. Let me set up your project..."

---

## Phase 5: Create Constitution

Create `.specify/memory/constitution.md` using the interview answers.

**Template** (fill in ALL bracketed values):

```markdown
# {PROJECT_NAME} Constitution

> {PROJECT_VISION — paste their description here}

**Version:** 1.0.0

---

## Ralph Wiggum

**Source:** https://github.com/fstandhartinger/ralph-wiggum
**Commit:** {COMMIT_HASH}
**Installed:** {TODAY_DATE}

### Auto-Update

At session start, check for updates:
1. Run: `git ls-remote https://github.com/fstandhartinger/ralph-wiggum.git HEAD`
2. If hash differs: fetch latest scripts, update this file, inform user

---

## Context Detection

**Ralph Loop Mode** (you're in this if started by ralph-loop.sh):
- Focus on implementation — no unnecessary questions
- Pick highest priority incomplete spec
- Complete ALL acceptance criteria
- Test thoroughly
- Commit and push
- Output `<promise>DONE</promise>` ONLY when 100% complete

**Interactive Mode** (normal conversation):
- Be helpful and conversational
- Guide decisions, create specs
- Explain Ralph loop when ready

---

## Core Principles

### I. {PRINCIPLE_1}
{Brief description if provided}

### II. {PRINCIPLE_2}
{Brief description if provided}

### III. Simplicity
Build exactly what's needed, nothing more.

---

## Technical Stack

{Either list what user provided OR write: "Detected from codebase" and list what you found}

---

## Autonomy

**YOLO Mode:** {ENABLED/DISABLED}
{If enabled: Full permission to read/write files, execute commands, make HTTP requests}

**Git Autonomy:** {ENABLED/DISABLED}
{If enabled: Commit and push without asking, meaningful commit messages}

---

## Work Items

The agent discovers work dynamically from:
1. **specs/ folder** — Primary source, look for incomplete `.md` files
2. **GitHub Issues** — If this is a GitHub repo
3. **IMPLEMENTATION_PLAN.md** — If it exists
4. **Any task tracker** — Jira, Linear, etc. if configured

Create specs using `/speckit.specify [description]` or manually create `specs/NNN-feature-name.md`.

Each spec MUST have **testable acceptance criteria**.

### Re-Verification Mode

When all specs appear complete, the agent will:
1. Randomly pick a completed spec
2. Strictly re-verify ALL acceptance criteria
3. Fix any regressions found
4. Only output `<promise>DONE</promise>` if quality confirmed

---

## Running Ralph

```bash
# Claude Code / Cursor
./scripts/ralph-loop.sh

# OpenAI Codex
./scripts/ralph-loop-codex.sh

# With iteration limit
./scripts/ralph-loop.sh 20
```

---

## Completion Signal

When a spec is 100% complete:
1. All acceptance criteria verified
2. Tests pass
3. Changes committed and pushed
4. Output: `<promise>DONE</promise>`

**Never output this until truly complete.**
```

---

## Phase 6: Create Agent Entry Files

### AGENTS.md (project root)

```markdown
# Agent Instructions

**Read:** `.specify/memory/constitution.md`

That file is your source of truth for this project.
```

### CLAUDE.md (project root)

Same content as AGENTS.md.

---

## Phase 7: Create Prompts

> **Note:** Both `ralph-loop.sh` and `ralph-loop-codex.sh` will auto-create these files if missing.
> You can still create them manually for customization.

### PROMPT_build.md

```markdown
# Ralph Build Mode

Read `.specify/memory/constitution.md` first.

## Your Task

1. Check `specs/` folder
2. Find highest priority INCOMPLETE spec
3. Implement completely
4. Run tests, verify acceptance criteria
5. Commit and push
6. Output `<promise>DONE</promise>` when done

## Rules

- ONE spec per iteration
- Do NOT output magic phrase until truly complete
- If blocked: explain in ralph_history.txt, exit without phrase
```

### PROMPT_plan.md (optional)

```markdown
# Ralph Planning Mode

Read `.specify/memory/constitution.md` first.

## Your Task

1. Analyze specs in `specs/`
2. Create `IMPLEMENTATION_PLAN.md` with prioritized tasks
3. Output `<promise>DONE</promise>` when done

Delete IMPLEMENTATION_PLAN.md to return to direct spec mode.
```

---

## Phase 8: Create Cursor Command

Create `.cursor/commands/speckit.specify.md`:

```markdown
---
description: Create a feature specification
---

Create a specification for:

$ARGUMENTS

## Steps

1. Generate short name (2-4 words, kebab-case)
2. Find next spec number from `specs/`
3. Create `specs/NNN-short-name.md`
4. Include clear acceptance criteria
5. Add completion signal:
   ```
   **Output when complete:** `<promise>DONE</promise>`
   ```
```

---

## Phase 9: Explain Next Steps

Present this clearly to the user:

---

### Ralph Wiggum is Ready!

Here's what was created:

| File | Purpose |
|------|---------|
| `.specify/memory/constitution.md` | Your project's guiding document |
| `scripts/ralph-loop.sh` | The autonomous build loop (Claude/Cursor) |
| `scripts/ralph-loop-codex.sh` | The autonomous build loop (Codex) |
| `AGENTS.md` / `CLAUDE.md` | Entry points for AI agents |
| `PROMPT_build.md` | Instructions for build mode |

---

### How to Use Ralph

**Step 1: Create Specifications**

Tell me what you want to build:

```
"Create a spec for user authentication with OAuth"
```

Or use the Cursor command:
```
/speckit.specify user authentication with OAuth
```

Each spec needs **clear acceptance criteria** — specific, testable requirements that define "done."

**Step 2: Start the Loop**

Once you have specs, run:

```bash
# For Claude Code / Cursor
./scripts/ralph-loop.sh

# For Codex CLI
./scripts/ralph-loop-codex.sh
```

Ralph will:
1. Pick the highest priority incomplete spec (or a different one if the top priority seems unachievable or needs preconditions)
2. Track NR_OF_TRIES at the bottom of each spec — if it reaches 10, split the spec into simpler ones
3. Check `history/` folder for lessons learned from previous attempts
4. Implement the spec completely
5. Add concise notes to `history/` about what was learned
6. Verify all acceptance criteria
7. Commit and push (and deploy if needed)
8. Move to the next spec
9. Repeat until all specs are done

---

### The Magic of Ralph

```
┌─────────┐   ┌─────────┐   ┌─────────┐
│ Loop 1  │ → │ Loop 2  │ → │ Loop 3  │ → ...
│ Spec A  │   │ Spec B  │   │ Spec C  │
│  DONE   │   │  DONE   │   │  DONE   │
└─────────┘   └─────────┘   └─────────┘
     ↑             ↑             ↑
   Fresh        Fresh         Fresh
  Context      Context       Context
```

Each iteration starts with a fresh context window. No context overflow, no degradation.

---

### Quick Reference

| Task | Command |
|------|---------|
| Create spec | Tell me or `/speckit.specify [feature]` |
| Start building | `./scripts/ralph-loop.sh` |
| Use Codex | `./scripts/ralph-loop-codex.sh` |
| Limit iterations | `./scripts/ralph-loop.sh 20` |

---

Ready to create your first specification?
