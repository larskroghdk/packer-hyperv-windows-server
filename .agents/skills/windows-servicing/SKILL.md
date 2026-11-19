---
name: windows-servicing
description: Maintain this factory's feature, Windows Update and approved offline-package servicing.
---

Read ../../../docs/plugin-audit.md and ../../../docs/operations.md. Server Manager names NET-Framework-Core and PowerShell-V2 differ from DISM identities such as NetFx3. Source payload must come from the same approved media. Offline MSUs use WUSA SYSTEM tasks via windows-restart restart_command, one prerequisite/reboot boundary at a time. rgl update retries failures; timeout bounds successful cycles. Do not add report_path to its schema or assume Catalog OOB availability through WUA.
