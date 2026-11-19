---
name: windows-setup
description: Maintain this factory's Windows Server unattended installation and WinRM bootstrap.
---

Read scripts/bootstrap/Bootstrap.ps1 and http/autounattend/Autounattend.xml.pkrtpl together. The setup answer file goes on a secondary CD; PACKER_BOOT identifies it independent of drive letters. Install partition 3 follows EFI/MSR. Preserve XML escaping of sensitive values and absence of autologon. Validate exact WIM/ESD name, release build, edition and installation type with approved media and Windows SIM before live qualification.
