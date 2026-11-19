# Implementation report

Implementation date: 2026-11-19. Repository: packer-hyperv-windows-server.

## Delivered

Shared HCL2 source/build logic, three release variable files, configurable Standard/Datacenter Core/Desktop selection, Gen 2 UEFI/MicrosoftWindows Secure Boot, configurable resources/switch/timeouts, verified ISO checksums, unattend GPT setup, scoped HTTPS/NTLM bootstrap, feature payload staging and sensitive credentials.

The provisioning pipeline uses the actual four custom plugin interfaces and the user-approved rgl/windows-update 0.18.4 alternative. It removes or verifies absent PowerShell 2, installs .NET 3.5, optimizes, hardens, installs approved offline packages with per-package Packer restart boundaries, runs online update/reboot/rescan, cleans through supported servicing, and validates the final guest. Sysprep runs through a detached SYSTEM finalizer initiated by the builder shutdown command. Offline VHDX verification gates the release manifest and SHA256.

Host orchestration validates approved media/image identity and host capabilities, creates unique resources, refuses replacement, captures evidence and optionally copies verified artifacts to existing external storage. Added hosted static CI, protected manual self-hosted live CI, static/negative checks, authorized live-test entrypoint and consistent Codex/Claude/Copilot guidance.

## Verification

- Packer 1.16.2 on Windows; Hyper-V plugin 1.1.5 and update plugin 0.18.4 downloaded through init.
- Compiled all four custom plugins from their existing clean source trees into an ignored workspace directory. Registered them through the supported packer plugins install --path mechanism. Source repositories were not edited.
- Full Packer schema validation passed for 2019, 2022 and 2025, Core and Desktop. The optional OOB dynamic blocks are also validated with inert local file fixtures.
- Invalid release/edition/checksum/CPU/build-ID values are rejected. Formatting, PowerShell AST, XML credential escaping, pipeline/shutdown invariants and documentation links are included in the repeatable static suite.
- Final Windows PowerShell 5.1 run passed 80 static checks, including the six release/type cases and nonempty offline-package block validation. Manifest serialization, SHA256 and rejection of failed offline or pending hardening evidence passed. The embedded finalizer script is parsed independently; bootstrap/staging/firewall names are checked across stages. Both workflow YAML files parsed, and all ten project skills passed the skill validator. Evidence is in reports/static-validation.log.
- The configuration-only Build.ps1 entrypoint completed successfully without creating a VM. A nondefault .NET staging subdirectory passed full schema validation. Bootstrap changes to ImageFactory naming were propagated through dependent paths and cleanup rules.
- Exact local plugin commits and installation limitations are recorded in [plugin audit](plugin-audit.md). Local provenance output is .validation/plugin-provenance.json.

## Dependencies and qualification limits

No live VM builds, Sysprep execution, captured VHDX, real ISO validation, update-source integration or deployment smoke tests were performed. Hyper-V and oscdimg were discovered on this host, but no approved ISO/site settings/build secret or explicit live-build authorization was supplied. Static validation emitted the builder's low-memory warning. These limitations prevent describing the resulting images as production certified; the six live release/type cases remain release gates.

The custom windows-update source repository is absent. The user approved upstream rgl/windows-update as a substitution. The four other custom sources currently return no release found from packer init; local source installation works, but signed downloadable releases remain an external dependency for release-only installation. CI needs access to the pinned plugin repositories/commits.

Only English x64 installation media is implemented, with configurable region/keyboard/time zone. Use volume/evaluation media with noninteractive edition selection; other license channels require further answer-file qualification. A dedicated WinRE partition is not created. Build transport uses scoped HTTPS with a self-signed bootstrap certificate on an isolated trusted network. Hardening compatibility deferrals and baseline exclusions are retained in reports and must be reviewed; complete baseline compliance is not asserted.

The update stage is bounded by a total timeout and failure retry count, not a configurable count of successful reboot cycles. Approved OOB/checkpoint prerequisites must be supplied in vendor order with trusted hashes. Update completeness is relative to the configured source/search policy. The finalizer removes known factory artifacts and invalidates the build credential; runner/TEMP/cache disposal and encryption remain host operational responsibilities.

Use [operations](operations.md) to qualify and run real images. No sibling plugin repository was modified, no changes were committed or pushed, and no workflow was dispatched.
