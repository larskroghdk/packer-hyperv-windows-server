# Agent instructions

Build and maintain a Windows Server image factory using the implemented Packer plugin interfaces. Read [the plugin audit](docs/plugin-audit.md) before changing provisioning, and [the operating guide](docs/operations.md) before running builds. The shared project procedure is [.agents/skills/image-factory/SKILL.md](.agents/skills/image-factory/SKILL.md).

- Preserve the shared HCL pipeline and version-specific variable files. Core and Desktop share the same source.
- Inspect Config, generated HCL2Spec, registration, guest actions and tests before using a plugin option. Do not modify sibling plugin repositories.
- Preserve elevated native PowerShell 5.1, .NET 4.x, WinRM, networking, firewall protection, Defender and update dependencies.
- Keep scripts limited to bootstrap, offline approved-package bridging, evidence, host orchestration and generalization. Use plugins for their implemented operations.
- Never write build credentials to tracked files, settings, CLI arguments or reports. Answer media is sensitive; see operating guidance for isolation and disposal.
- Preserve exact-file cleanup manifests. Never delete WinSxS, Installer, SoftwareDistribution, Catroot2 or servicing metadata manually.
- Use plugin-owned bounded restarts. Offline packages use the documented windows-restart restart_command. Sysprep belongs to the builder shutdown lifecycle.
- Do not provision a guest after Sysprep. Offline verification must read a detached disk without booting it.
- Run tests/static/Test-Project.ps1 after changes. Report failed or unavailable checks accurately. Syntax checks do not certify image behavior.
- Live tests require an explicit -AuthorizeLiveBuild or -Build invocation on a dedicated host. Do not alter existing VMs, switches or media. Never use packer -force.
- Keep docs, CI pins and dependency records aligned. Record limitations, compatibility deferrals and source provenance. Do not claim complete Microsoft baseline compliance when the plugin defers settings.
- Maintain the examples directory when configuration or build commands change. Include usable instructions for Core/Desktop and approved offline packages without embedding real credentials or claiming example media identities are approved.
