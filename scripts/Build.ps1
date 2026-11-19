[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('2019','2022','2025')][string]$Version, [Parameter(Mandatory)][string]$SettingsPath, [switch]$Build, [string]$ExternalStorage)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$vars = @{}
foreach ($property in $settings.PSObject.Properties) { $vars[$property.Name] = $property.Value }
if ($vars.ContainsKey('administrator_password')) { throw 'Do not put passwords in settings. Set PKR_VAR_administrator_password from a secret store.' }
foreach ($key in 'iso_path','iso_checksum','image_name','switch_name','winrm_allowed_address','image_version') {
    if (-not $vars.ContainsKey($key) -or -not $vars[$key]) { throw "Missing setting: $key" }
}
$vars.server_version = $Version
if (-not $vars.ContainsKey('edition')) { $vars.edition = 'Datacenter' }
if (-not $vars.ContainsKey('installation_type')) { $vars.installation_type = 'Core' }
$vars.build_id = [guid]::NewGuid().ToString('N').Substring(0,12)
if (-not $vars.ContainsKey('output_directory')) { $vars.output_directory = 'output' }
if (-not $vars.ContainsKey('report_directory')) { $vars.report_directory = 'reports' }
if (-not $vars.ContainsKey('approved_oob_packages')) { $vars.approved_oob_packages = @() }
if ($vars.edition -notin 'Standard','Datacenter' -or $vars.installation_type -notin 'Core','Desktop' -or $vars.image_version -notmatch '^[0-9][0-9A-Za-z._-]{0,39}$') { throw 'Invalid edition, installation type or image version.' }
if (-not $env:PKR_VAR_administrator_password) { throw 'Set PKR_VAR_administrator_password using a unique build credential from your secret store.' }
$id = "ws$Version-$($vars.edition.ToLower())-$($vars.installation_type.ToLower())-$($vars.image_version)-$($vars.build_id)"
$report = Join-Path $vars.report_directory $id
New-Item -ItemType Directory -Path $report -Force | Out-Null
$start = [DateTime]::UtcNow
$varPath = Join-Path $report 'build-input.pkrvars.json'
$vars | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $varPath -Encoding utf8
function Invoke-Packer([string[]]$Arguments) {
    & packer @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Packer $($Arguments[0]) failed with exit $LASTEXITCODE" }
}
$scratch = $null
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$status = 'failed'
try {
    Invoke-Packer @('init', '.')
    Invoke-Packer @('fmt', '-check', '-recursive', '.')
    Invoke-Packer @('validate', "-var-file=config/windows-server-$Version.pkrvars.hcl", "-var-file=$varPath", '.')
    if (-not $Build) { $status = 'configuration_validated'; Write-Output "Configuration validated. Add -Build to authorize creation and disposal of an isolated build VM ($id)."; return }
    & "$PSScriptRoot/Test-Host.ps1" -Variables $vars
    if (Get-VM -Name $id -ErrorAction SilentlyContinue) { throw 'Build VM name already exists; refusing to reuse it.' }
    $output = Join-Path $vars.output_directory $id
    if (Test-Path -LiteralPath $output) { throw 'Output path already exists; use a fresh build ID.' }
    # Packer's generated answer CD contains a secret. Give it a private, known
    # TEMP root and remove that root on success or failure.
    $scratchRoot = [IO.Path]::GetFullPath((Join-Path $PWD '.build'))
    New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
    if ((Get-Item -LiteralPath $scratchRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Build scratch root must not be a link.' }
    $candidate = Join-Path $scratchRoot $vars.build_id
    if (Test-Path -LiteralPath $candidate) { throw 'Private temporary directory already exists.' }
    New-Item -ItemType Directory -Path $candidate | Out-Null
    $scratch = $candidate
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $scratch -AclObject $acl
    $env:TEMP = $scratch
    $env:TMP = $scratch
    # Packer handles only its newly created VM. No -force or ambient VM cleanup.
    # Windows PowerShell represents native stderr as ErrorRecords. Preserve
    # diagnostics and use the process exit code as the success contract.
    $ErrorActionPreference = 'Continue'
    try {
        & packer build -on-error=cleanup "-var-file=config/windows-server-$Version.pkrvars.hcl" "-var-file=$varPath" . 2>&1 | Tee-Object -FilePath (Join-Path $report 'packer.log')
        $packerExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    if ($packerExit -ne 0) { throw "Packer build failed: $packerExit" }
    $disks = @(Get-ChildItem -LiteralPath $output -Recurse -Filter '*.vhdx' -File)
    if ($disks.Count -ne 1) { throw 'Expected exactly one output VHDX.' }
    & "$PSScriptRoot/Test-Image.ps1" -Path $disks[0].FullName -ReportPath (Join-Path $report 'offline-validation.json')
    & "$PSScriptRoot/New-Manifest.ps1" -Variables $vars -ReportDirectory $report -Vhdx $disks[0].FullName -StartedAt $start
    if ($ExternalStorage) {
        # External storage is a mounted SMB/volume destination; authentication is
        # provided by the runner identity, never a credential embedded in a URI.
        if (-not (Test-Path -LiteralPath $ExternalStorage -PathType Container)) { throw 'External storage must be an existing mounted destination.' }
        $destination = Join-Path $ExternalStorage $id
        if (Test-Path -LiteralPath $destination) { throw 'External image destination exists; refusing overwrite.' }
        New-Item -ItemType Directory -Path $destination | Out-Null
        Copy-Item -LiteralPath $disks[0].FullName -Destination $destination
        $copy = Join-Path $destination $disks[0].Name
        if ((Get-FileHash $copy).Hash -ne (Get-FileHash $disks[0].FullName).Hash) { throw 'External storage checksum verification failed.' }
        Copy-Item -Path (Join-Path $report '*.json') -Destination $destination
        Copy-Item -Path (Join-Path $report '*.sha256') -Destination $destination
    }
    $status = 'release_validated'
} finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    if ($scratch -and (Test-Path -LiteralPath $scratch)) {
        $resolved = (Resolve-Path -LiteralPath $scratch).Path
        $expected = [IO.Path]::GetFullPath((Join-Path $scratchRoot $vars.build_id))
        if ($resolved -ne $expected -or -not $resolved.StartsWith($scratchRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or ((Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing temporary cleanup outside the verified build scratch directory.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    @{ schema_version=1; image_id=$id; status=$status; started_at=$start.ToString('o'); finished_at=[DateTime]::UtcNow.ToString('o'); build_requested=[bool]$Build } | ConvertTo-Json | Set-Content (Join-Path $report 'invocation.json')
}
