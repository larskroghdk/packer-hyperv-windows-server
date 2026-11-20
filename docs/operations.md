# 📘 Operations

## 🔐 Media, configuration and secrets

Obtain English x64 Server 2019/2022/2025 media from Microsoft licensing/subscription or Evaluation Center channels and independently approve its SHA256. A matching hash establishes the approved file identity; it does not establish provenance if the expected hash came from an untrusted download. Evaluation licensing/expiry and activation remain operator responsibilities. This factory does not distribute ISO media or license keys. Use volume/evaluation media that permits edition selection without an interactive product-key prompt; qualify other channels with Windows SIM first.

Config files select release, edition and Core/Desktop. Required site inputs are iso_path, iso_checksum, exact image_name, switch_name, winrm_allowed_address and image_version. All variables are documented in variables.pkr.hcl. The wrapper passes private JSON as an additional Packer variable file and reads only the password from PKR_VAR_administrator_password. Direct Packer invocation also needs a unique build_id and an existing report directory for file download. Use the wrapper for release artifacts and host/offline checks.

WinRM always uses HTTPS and NTLM. Bootstrap creates a short-lived self-signed certificate, so Packer skips PKI validation. Use an isolated trusted build network and restrict the guest firewall to the host IP/CIDR. Do not use this setup across an untrusted network. Port is configurable; transport downgrade is intentionally unsupported. No autologon is configured. English media is required for the built-in Administrator name; region/keyboard/time zone are configurable.

The generated answer CD necessarily contains the temporary administrator password in XML. Packer sensitivity prevents normal UI display, not recovery from media or arbitrary debug logs. Build.ps1 sets a private ACL-protected TEMP directory for the live build and removes that verified scratch path in its finally block. Restrict runner identity, workspace/cache access and storage encryption. Do not enable PACKER_LOG or upload answer media, caches or VM working directories. Use a fresh runner workspace and unique build secret; after a process/host crash, dispose residual .build directories and rotate the injected secret. Only reports/output VHDX are eligible for publishing. The finalizer invalidates the password, removes bootstrap certificate/listeners/rule and autologon values, and Sysprep resets the built-in Administrator for server OOBE.

Unattend creates an EFI partition, MSR and Windows partition. There is no dedicated WinRE recovery partition; these are server VM base images and recovery is provided by redeployment/backups. Qualify a separate recovery layout if your deployment policy requires one. Extra disks and domain-controller images are outside this factory's scope.

## 🛡️ Servicing and hardening

PowerShell-V2 removal skips unavailable features; final validation checks absence/disabled state and preserves PowerShell 5.1. .NET 3.5 installs only from sources/sxs staged from the same verified ISO. netfx_source chooses its staging subdirectory within the cleanup plugin's approved staging root; bootstrap, feature installation and cleanup use the same configured path. Features and optimization verify their own post-reboot state. Hardening uses a Microsoft baseline implementation in compatibility mode, which may defer connectivity-breaking controls. Review deferred_plan and baseline exclusions before approving an image for a workload. This is not a complete baseline-compliance assertion.

The requested main stage order is retained. Offline approved MSUs are installed between hardening and online updates so online servicing can resolve supersedence and remaining updates. The online default installs applicable non-hidden software updates except Preview titles, including security/cumulative/servicing-stack updates offered by the configured Windows Update/WSUS source. It does not silently enroll the guest in Microsoft Update or change WSUS policy. The final scan uses the same selection rule and fails if required updates remain. Change update_search_criteria only under an approved servicing policy; narrowing it narrows the completeness assertion too.

For an OOB release, place approved MSUs on the host and set approved_oob_packages to an ordered array of objects with path, sha256 and kb. Include all required checkpoint/servicing-stack prerequisites in the vendor-prescribed order. Each unique KB is hash checked on host and guest, installed through WUSA as SYSTEM, and restarted through Packer windows-restart before continuing. WUSA errors, unsupported packages and missing installed/superseded KB evidence fail the build. This does not discover or automatically approve Catalog downloads. Empty arrays are the normal configuration.

The online update provisioner owns its install/reboot/rescan loop. Its retry count handles failures; successful cycles are bounded by update_timeout (default six hours). The outer workflow has a twelve-hour cap. Feature restarts and reconnects have their own limits. The extra post-update windows-restart drains servicing before cleanup. Read-only optimization/hardening plugin passes then verify that servicing did not undo the selected settings; failed/pending results block release. Cleanup performs supported component cleanup, retains servicing/event diagnostics and does not ResetBase. A residual pending reboot after cleanup/final scan fails validation rather than starting an unbounded loop.

## 📦 Generalization and deployment

Final guest validation records features, QFE updates, DISM packages, update history, a fresh applicability search, component-store health, Secure Boot/GPT and reboot state. Cleanup removes cached unattend files and explicitly listed staging/Temp artifacts. The finalizer is staged last; the Hyper-V shutdown_command schedules a delayed SYSTEM worker and returns while connectivity is still present. That worker closes temporary access, invalidates the build password, removes its own staging/task, and invokes Sysprep /generalize /oobe /shutdown. Failure writes generalization-error.txt and deliberately does not shut down.

The builder waits for power-off without waiting for a provisioner to survive WinRM loss. The wrapper mounts the detached VHDX read-only, copies its registry hive to scratch, checks IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE and known artifact absence, then unmounts. It never boots the base image. Only then is the release manifest/checksum created. Do not publish output from failed or directly invoked Packer builds without these checks.

Deploy from a copy of the generalized VHDX with a separate consumer unattend process that establishes the administrator password, identity, network and management certificate/listeners. The base image deliberately retains no build management listener. Do not boot the canonical artifact. Preserve Sysprep/CBS/DISM diagnostics for troubleshooting.

## 🧪 Validation and release qualification

Run tests/static/Test-Project.ps1 for AST parsing, XML parsing/credential escaping, pipeline invariants, documentation links, plugin discovery, init/fmt, six schema validations and rejected invalid variables. Static fixtures use a reserved documentation address, fake checksum/media path and a public non-production credential. They never create VMs and do not test real installation media.

With real site settings and an injected secret, these direct commands also work once all required inputs are supplied through PKR_VAR_* or a private auto.pkrvars file:

```powershell
packer init .
packer fmt -check -recursive .
packer validate '-var-file=config/windows-server-2019.pkrvars.hcl' .
packer validate '-var-file=config/windows-server-2022.pkrvars.hcl' .
packer validate '-var-file=config/windows-server-2025.pkrvars.hcl' .
```

Run tests/live/Test-Build.ps1 -Version 2022 -SettingsPath C:/Private/ws2022.json -AuthorizeLiveBuild only when authorized. Repeat for all three releases and both installation types, plus any edition/channel actually shipped. Validate answer files with Windows SIM against each approved image. Release evidence must include live logs, reports, manifest, offline state, checksum and a disposable deployment smoke test made from a copy. That last consumer-specific smoke test is a separate authorization and is not performed by this repository.

On failure, inspect reports/packer.log, the relevant plugin report and guest Panther/CBS/DISM logs if accessible. Packer disposes its own failed VM by default; reproduce on a disposable host with an approved diagnostics plan if guest logs must be recovered. Never retry servicing blindly while a prior servicing task may still be active. The wrapper refuses existing output paths and VM names and never forces replacement. No live tests ran during implementation.

## 🗄️ CI and storage

validate.yml runs on hosted Windows for pushes/PRs, builds the four plugins from audited commit pins, runs static checks and uploads evidence. Source repositories/commits must be reachable by the checkout token. No live host or build secret is exposed to pull requests. Update pins through reviewed changes; do not treat local development binaries as signed releases.

build.yml is manual, trusted-main-only, and requires authorize_live_build plus the hyperv-build environment. Configure environment reviewers, the dedicated self-hosted Windows/X64/hyperv-image-factory runner, Packer/Hyper-V/ADK prerequisites, preinstalled audited plugins, PACKER_PLUGIN_PATH repository variable and PACKER_ADMINISTRATOR_PASSWORD environment secret. Use a one-use secret or automated runner secret rotation. The runner must be elevated and exclusively reserved for trusted image builds; never run untrusted PR jobs there.

Keep site output_directory/report_directory at output/reports for workflow artifact discovery. Logs/JSON/manifests/checksums upload even on failure. VHDX upload is optional and occurs only after successful wrapper validation. Large disks should use external_storage: an existing mounted volume/SMB directory authenticated by the runner identity. Copies get a fresh image-ID directory and are hash verified before manifest copy; existing destinations are never overwritten. Storage credentials must not be embedded in paths. Set retention and access policy on your external store separately.
