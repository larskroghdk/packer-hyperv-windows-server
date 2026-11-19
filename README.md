# Windows Server template factory

Shared Packer HCL2 builds Windows Server 2019, 2022 and 2025 Standard/Datacenter, Core or Desktop Experience, from approved English Microsoft ISO media. Output is a standalone generalized Generation 2 VHDX with Secure Boot, provisioning reports, a JSON manifest and SHA256.

**Qualification status:** all six release/installation configurations pass Packer schema validation against real plugin binaries. No live Windows image has been built or certified in this implementation session. See [implementation results](docs/implementation-report.md) and [plugin audit](docs/plugin-audit.md).

The update stage uses `rgl/windows-update` v0.18.4, approved in place of the unavailable custom update repository. Feature, optimization, hardening and cleanup operations use the four existing custom plugins without modifying their repositories.

## Run

See [configuration and command examples](examples/README.md) for all three releases, Core/Desktop settings, validation, live builds, external storage and approved OOB/checkpoint packages.

Use an elevated dedicated Windows Hyper-V host with Packer 1.16.2, Windows ADK Deployment Tools (`oscdimg` on PATH), native Windows PowerShell 5.1, the Hyper-V/DISM modules, sufficient disk/RAM, DHCP, and update-source connectivity. Reserve at least 4 GB guest RAM plus host overhead and roughly three times the provisioned disk size for working/export space. Use an isolated switch reachable from the build host.

Custom plugin releases are currently unavailable through `packer init`. With Go 1.26+ and the sibling source repositories, install local binaries into this repository's ignored plugin directory:

```powershell
./scripts/Install-LocalPlugins.ps1
$env:PACKER_PLUGIN_PATH = "$PWD/.validation/plugins"
packer init .
./tests/static/Test-Project.ps1
```

Copy [settings.example.json](config/settings.example.json) to a private settings file. Replace its example ISO path, all-zero SHA256, exact image name, switch and permitted host address with approved values. The example checksum is deliberately unusable for a real build. Specify `installation_type` as `Desktop` to select Desktop Experience and set its matching exact image name. Regional locale, keyboard and time zone are optional overrides. Do not put credentials in settings.

Inject `PKR_VAR_administrator_password` from your secret manager using a unique complex password for each build. Then validate configuration or explicitly start an isolated build:

```powershell
./scripts/Build.ps1 -Version 2022 -SettingsPath C:/Private/ws2022.json
./scripts/Build.ps1 -Version 2022 -SettingsPath C:/Private/ws2022.json -Build
```

`-Build` authorizes creation and automatic disposal of the newly named build VM. No existing VM or switch is reused or removed. The script checks ISO checksum, WIM/ESD release, edition, Core/Desktop type, architecture, English UI and .NET payload before creating a VM. Exact image names vary between evaluation, volume and other Microsoft media; inspect them with `Get-WindowsImage` rather than guessing indexes.

## Pipeline and output

Unattended GPT/UEFI setup → HTTPS WinRM → remove PowerShell 2 → install .NET 3.5 → optimize → harden → approved offline packages and bounded restarts → Windows Update → restart → supported cleanup → health/feature/update validation → builder-owned Sysprep → shutdown → capture → offline generalized-state validation → manifest/checksum.

The wrapper produces `output/ws<release>-<edition>-<type>-<version>-<unique-id>/Virtual Hard Disks/*.vhdx`. Corresponding `reports/<same-id>/` contains plugin JSON, guest/offline validations, Windows Update evidence, Packer manifest/log and the versioned release manifest/checksum. A successful `packer build` alone is insufficient: `Build.ps1` must pass offline validation before issuing the release manifest.

Read [operations](docs/operations.md) for security, OOB/checkpoint approval, failure handling, testing, deployment and CI. The reference configuration and its limitations are in [the plugin audit](docs/plugin-audit.md). Engineering instructions are in [AGENTS.md](AGENTS.md).
