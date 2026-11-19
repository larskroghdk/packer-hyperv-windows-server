---
name: powershell-guest
description: Edit this factory's Windows PowerShell 5.1 guest scripts and host orchestration.
---

Guest scripts run under native elevated 5.1, not pwsh. Avoid PowerShell 7-only syntax and inspect native process exit codes explicitly. Keep credentials out of argv and files. Scripts uploaded by the powershell provisioner have generated remote paths: do not rely on adjacent repository files in PSScriptRoot. The bootstrap script is the exception because it runs directly from the answer CD. Parse and exercise host-side evidence functions with synthetic fixtures before release.
