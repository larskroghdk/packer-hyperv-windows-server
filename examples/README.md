# Configuration and command examples

Run commands from the repository root. These examples contain deliberately unusable media identifiers: replace the ISO path, zero SHA256, exact image name, switch and documentation-only host IP with your approved values. Credentials belong in PKR_VAR_administrator_password, injected from your secret manager. No example authorizes a live build by itself.

| Release | Server Core | Desktop Experience |
| --- | --- | --- |
| 2019 | [Core settings](windows-server-2019-core.settings.json) | [Desktop settings](windows-server-2019-desktop.settings.json) |
| 2022 | [Core settings](windows-server-2022-core.settings.json) | [Desktop settings](windows-server-2022-desktop.settings.json) |
| 2025 | [Core settings](windows-server-2025-core.settings.json) | [Desktop settings](windows-server-2025-desktop.settings.json) |

Each file shows Datacenter; set edition to Standard and select its matching exact image name for Standard. Copy the selected file to a private location before editing it. The -Version argument must match the selected media release.

## Validate and build

After installing the plugins as described in [the main README](../README.md):

```powershell
# Static project checks; no VM or real installation media required.
$env:PACKER_PLUGIN_PATH = "$PWD/.validation/plugins"
./tests/static/Test-Project.ps1

# With your private settings and injected build secret, validate configuration.
./scripts/Build.ps1 -Version 2022 -SettingsPath C:/Private/ws2022-core.json

# Explicitly authorize an isolated live build and its automatic VM disposal.
./scripts/Build.ps1 -Version 2022 -SettingsPath C:/Private/ws2022-core.json -Build

# Desktop Experience uses the corresponding Desktop settings/image name.
./scripts/Build.ps1 -Version 2025 -SettingsPath C:/Private/ws2025-desktop.json -Build

# Copy a validated image to an existing mounted destination, with hash checking.
./scripts/Build.ps1 -Version 2019 -SettingsPath C:/Private/ws2019-core.json -Build -ExternalStorage X:/ApprovedImages
```

Configuration-only validation checks Packer settings. Actual ISO identity and host prerequisites are checked when -Build is requested. See [operations](../docs/operations.md) for the full qualification requirements.

## Approved OOB and checkpoint packages

Use this snippet to construct the approved_oob_packages array for your private settings. Supply Microsoft-approved files and independently verified hashes, adding prerequisite packages first. Computing a hash does not establish that a download is trustworthy. Enter the actual KB identities; no fictional KB is assumed to be an available update.

```powershell
$settingsPath = 'C:/Private/ws2025-core.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$packages = @()
do {
    $path = Read-Host 'Absolute path to the next approved MSU (prerequisites first)'
    $kb = Read-Host 'Actual KB identity, including KB prefix'
    if ($kb -notmatch '^KB[0-9]+$') { throw 'Invalid KB identity' }
    $file = Get-Item -LiteralPath $path
    if ($file.Extension -ne '.msu') { throw 'Select an approved MSU file' }
    $packages += [ordered]@{
        path = $file.FullName
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        kb = $kb
    }
} while ((Read-Host 'Add another approved package? y/N') -eq 'y')
$settings.approved_oob_packages = $packages
$settings | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

# Review package order and compare hashes with the approved release record.
./scripts/Build.ps1 -Version 2025 -SettingsPath $settingsPath
```

The existing pipeline installs and restarts between packages, then runs online servicing and final verification. See [the plugin audit](../docs/plugin-audit.md) for the upstream update plugin's actual capabilities.
