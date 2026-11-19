---
name: hyperv-host
description: Inspect and maintain this factory's Hyper-V host prerequisites, resource isolation and VHDX capture.
---

Use scripts/Test-Host.ps1 before creation. Preserve Gen 2, MicrosoftWindows Secure Boot and standalone VHDX output. Do not infer host readiness from packer validate, which can pass without Hyper-V. Only explicitly authorized Build.ps1 -Build or live tests create VMs. Test-Image.ps1 reads a detached image without booting it and checks the offline generalized registry state before release.
