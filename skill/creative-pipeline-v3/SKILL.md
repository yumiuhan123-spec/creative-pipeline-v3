---
name: creative-pipeline-v3
description: Run a file-driven main-image planning workflow from scattered product materials through input inventory, evidence-based analysis, three six-image candidate schemes, human selection, six natural-language Image 2 prompts, and concurrent submission to six logged-in ChatGPT Edge tabs. Use when Codex needs to start, continue, inspect, approve, revise, or run a 主图方案生成 V3 project whose behavior is controlled by project-local workflow and instruction files.
---

# Creative Pipeline V3

Treat the project folder as the source of truth. Keep this Skill as a thin
orchestrator; do not duplicate P1-P5 business instructions here.

## Resolve The Project

1. Use a project path explicitly supplied by the user.
2. Otherwise walk upward from the current directory until
   `00_project/workflow.json` exists.
3. Refuse to run if `00_project/workflow.json` or
   `00_project/status.json` is missing.

Use `scripts/resolve_project.ps1` when deterministic resolution is helpful.

## Run The Current Phase

1. Read `00_project/workflow.json`.
2. Read `00_project/status.json`.
3. Find the phase matching `status.phase`.
4. Read that phase's `instruction` file completely before doing phase work.
5. Read only the additional files required by that instruction.
6. Perform the reasoning with Codex and write every required output into the
   project paths declared by the workflow.
7. Update `status.json`, `decisions.md`, and other machine-readable indexes
   required by the project instruction.
8. Stop at each gate and wait for explicit user approval. Never infer approval
   from silence.
9. If `workflow.json` defines `human_review`, use its entry file and real output
   paths when explaining how the user can inspect or edit results. Do not create
   review copies of schemes or prompts.
10. At P3 and P4 gates, report the exact project output paths and point the user
   to `人工审核区`. Never report only that generation is complete.

Project-local instruction files override general phrasing in this Skill. They
may change analysis methods, output fields, prompt style, browser conditions,
or other main functionality without editing the Skill.

## Phase Boundaries

- P1: Inventory `01_inputs`; do not analyze schemes.
- P2: Produce evidence-based analysis; do not select a scheme.
- P3: Produce three six-image schemes; stop for human selection.
- P4: Produce six prompt drafts; stop for human approval before finalizing.
- P5: Run the project browser wrapper only after all project approvals pass.

The phase instruction defines the detailed behavior and required files.

At P3 and P4 gates, tell the user where the real output files are and point to
the project-local `人工审核区` launcher when configured. Treat edits made
through that entry as edits to the authoritative project files.

## Browser Execution

For P5, run from the project root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "07_browser_jobs/scripts/run_distribution.ps1"
```

Do not use screenshots, coordinate clicking, or manual prompt transfer in the
normal path. Do not resubmit jobs that the log marks as submitted.

## New Projects

Prefer the repository-level `scripts/new-project.ps1` command documented in
the installed package. If the current project is already a copied template,
start at P1. Never initialize over an existing project.
