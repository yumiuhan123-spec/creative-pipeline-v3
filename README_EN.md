# Creative Pipeline V3

A file-driven Codex workflow for planning six-image product listing sets.

It inventories product materials, produces evidence-based analysis, drafts three candidate six-image schemes, pauses for human selection, writes six natural-language prompts for modern image models, and submits them concurrently through a persistent logged-in Microsoft Edge session.

## Quick Start

Requirements: Windows 10/11, Codex Desktop, Microsoft Edge, a ChatGPT account with image generation access, and either Node.js 20+ with npm or the bundled Codex Node/Playwright runtime.

Install:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install.ps1"
```

Create a project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-project.ps1" `
  -Destination "D:\Projects\my-product" `
  -ProjectName "My Product"
```

Open the new project folder in Codex and enter:

```text
Use $creative-pipeline-v3 to run the current project. Execute P1 first, inspect the inputs, and stop for my confirmation.
```

The first browser run requires one manual ChatGPT login. The login is stored locally under `%LOCALAPPDATA%\CreativePipelineV3\EdgeProfile` and is never part of this repository.

See [README.md](README.md) for the complete Chinese documentation.
