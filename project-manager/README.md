# Project Manager

Project Manager keeps the Creative Pipeline four-room workspace maintainable.
It is independent from the main-image P1-P5 workflow and independent from the version manager.

## Commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" version-map
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" check-archives
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" sync-template -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" sync-template -Approve
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" sync-skill -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" sync-skill -Approve
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" update-workbench-context -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" update-workbench-context -Approve
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" rebuild-archive -Tag v3.2.0 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" rebuild-archive -Tag v3.2.0 -Approve
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" release -DryRun -SkipAI -BumpOverride patch -ReleaseIntent "Describe the completed change"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" release -Approve -SkipAI -BumpOverride patch -ReleaseIntent "Describe the completed change"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\project-manager\scripts\project-manager.ps1" release -DryRun -AiTimeoutSec 90 -MaxSnapshotFiles 12 -MaxFileChars 3000 -ReleaseIntent "Describe the completed change"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\run-maintenance-tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\run-maintenance-tests.ps1" -IncludeDeepSeek
```

## Safety

- `status`, `version-map`, and `check-archives` are read-only.
- `sync-template` backs up the current template before replacing it.
- `sync-skill` copies the repository `creative-pipeline-v3` Skill into the Codex skills folder.
- `update-workbench-context` refreshes the standard workbench handoff context with the current version, tags, and Git ahead count.
- `rebuild-archive` creates archives from Git tags and does not touch working projects.
- `release` runs the version manager, uses the four-room archive root, previews template sync, syncs the installed Skill, refreshes the workbench context, and reports final workspace status.
- `release` can call DeepSeek for release analysis by comparing previous and current changed-file snapshots; `-AiTimeoutSec` bounds the AI wait, while `-MaxSnapshotFiles` and `-MaxFileChars` bound the content sent for analysis.
- `tests\run-maintenance-tests.ps1` checks the maintenance layer without requiring product images. The DeepSeek network test is opt-in with `-IncludeDeepSeek`.
- `scripts\validate-release.ps1` runs the maintenance tests unless `CPV3_SKIP_MAINTENANCE_TESTS=1` is set by a child dry-run.
- Write operations require `-Approve`; use `-DryRun` to preview.
- The manager never copies from the studio back into the template room.
