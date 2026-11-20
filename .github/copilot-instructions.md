# GitHub Copilot instructions

This repository builds Windows Server images with Packer and Hyper-V. Follow
[AGENTS.md](../AGENTS.md), the shared source of project rules, and the
[image factory procedure](../.agents/skills/image-factory/SKILL.md). Load the
focused procedures relevant to the change.

Before changing provisioning, read the [plugin audit](../docs/plugin-audit.md)
and verify the implemented plugin interfaces. Before running a build, read the
[operating guide](../docs/operations.md). Preserve the shared Core/Desktop HCL
pipeline, plugin-owned operations and bounded restarts, and builder-owned
Sysprep shutdown. Do not provision or boot the base image after generalization.

Keep build credentials out of tracked files, settings, command-line arguments
and reports. Preserve protected Windows dependencies and exact-file cleanup
manifests. Live builds require explicit authorization on a dedicated host;
never replace existing VMs, switches or media, or use `packer -force`.

Keep documentation, examples, CI pins and dependency records aligned with the
implementation. Run `tests/static/Test-Project.ps1` after changes and report
failed or unavailable checks. Distinguish static/schema validation from live
image qualification, and record hardening deferrals without claiming complete
Microsoft baseline compliance.
