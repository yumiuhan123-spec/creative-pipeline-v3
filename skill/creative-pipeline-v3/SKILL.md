---
name: creative-pipeline-v3
description: Run a file-driven main-image planning workflow from scattered product materials through input inventory, evidence-based analysis, three six-image candidate schemes, human selection, six natural-language Image 2 prompts, and concurrent submission to six logged-in ChatGPT Edge tabs. Use when Codex needs to start, continue, inspect, approve, revise, or run a 主图方案生成 V3 project whose behavior is controlled by project-local workflow and instruction files.
---

# Creative Pipeline V3

Treat the project folder as the source of truth. Keep this Skill as a thin
orchestrator; do not duplicate P1-P5 business instructions here.

## V3.1 Architecture Files

When present, read these project-local files before phase work:

- `00_project/project.config.json`: project identity, directory map, and browser policy.
- `00_project/workflow.state.json`: forward-looking stage ledger for resume and audit.
- `00_project/status.json`: compatibility source for the active phase in V3.1.

V3.1 establishes the architecture files, but it does not fully replace
`status.json` yet. Use `status.phase` to choose the current P1-P5 phase, and
update `workflow.state.json` alongside `status.json` when the phase changes.

## Execution Modes

The default execution mode is `standard`. In standard mode, stop at every human
gate and wait for explicit approval.

Quick mode is allowed only when the user explicitly asks for quick mode in the
current request, or when `00_project/project.config.json` sets
`execution.mode` to `quick`. Do not infer quick mode from urgency or silence.

In quick mode:

1. Read the quick-mode instruction declared by `workflow.run_modes.quick.instruction`
   when present. In the default template this is
   `可编辑工作流提示词/P6_快速模式指令.md`.
2. Continue from P1 through P5 without stopping at ordinary P1/P3/P4 approval
   gates.
3. Still stop if critical product inputs are missing, if product claims cannot
   be verified, if ChatGPT login is not confirmed, or if browser preflight fails.
4. At P3, generate three schemes, then choose the strongest scheme or a reasoned
   hybrid automatically. Write the final choice into
   `05_selected_scheme/selected_scheme.md` and explain the decision in
   `05_selected_scheme/selection_notes.md`.
5. At P4, write both `06_prompts/draft/*.txt` and `06_prompts/final/*.txt`, then
   mark `06_prompts/prompt_index.json` as `approved`.
6. Before P5, set the project approval fields needed for browser submission and
   set `07_browser_jobs/batch_manifest.json` `submit` to `true`.
7. Record all automatic decisions and assumptions in `00_project/decisions.md`
   and `00_project/workflow.state.json`.

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

In quick mode, the P3 and P4 stops become automatic decision records instead of
conversation pauses. Critical blockers still stop the run.

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
