[CmdletBinding()]
param([Parameter(Mandatory)][hashtable]$Variables)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Live builds require an elevated dedicated Windows Hyper-V host.' }
foreach ($cmd in 'Get-VM','Get-VMSwitch','Mount-DiskImage','Get-WindowsImage','Mount-VHD') { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Missing prerequisite command: $cmd" } }
if (-not (Get-Command oscdimg.exe -ErrorAction SilentlyContinue)) { throw 'Install Windows ADK Deployment Tools and add oscdimg.exe to PATH.' }
if ((Get-Service vmms).Status -ne 'Running') { throw 'Hyper-V Virtual Machine Management service is not running.' }
if (-not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) { throw 'The Hyper-V hypervisor is not active; check host/nested virtualization support.' }
$memoryMB = if ($Variables.ContainsKey('memory_mb')) { [double]$Variables.memory_mb } else { 4096 }
if ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024 -lt $memoryMB + 1024) { throw 'Insufficient free physical memory for the guest plus host overhead.' }
Get-VMSwitch -Name $Variables.switch_name -ErrorAction Stop | Out-Null
if ($Variables.iso_checksum -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Approved ISO SHA256 is required.' }
$expectedHash = $Matches[1]
$iso = Get-Item -LiteralPath $Variables.iso_path
if ($iso.Extension -ne '.iso' -or -not [IO.Path]::IsPathRooted($iso.FullName)) { throw 'Use an absolute local ISO path.' }
if ((Get-FileHash -LiteralPath $iso.FullName -Algorithm SHA256).Hash -ne $expectedHash) { throw 'ISO checksum mismatch.' }
$disk = Get-DiskImage -ImagePath $iso.FullName -ErrorAction SilentlyContinue
$wasAttached = $disk -and $disk.Attached
try {
    if (-not $wasAttached) { Mount-DiskImage -ImagePath $iso.FullName -PassThru | Out-Null }
    $volumes = @(Get-DiskImage -ImagePath $iso.FullName | Get-Volume | Where-Object DriveLetter)
    if ($volumes.Count -ne 1) { throw 'Cannot determine installation ISO volume.' }
    $drive = "$($volumes[0].DriveLetter):"
    $imagePath = Join-Path $drive 'sources\install.wim'
    if (-not (Test-Path $imagePath)) { $imagePath = Join-Path $drive 'sources\install.esd' }
    if (-not (Test-Path $imagePath)) { throw 'ISO has no supported install.wim/install.esd.' }
    $images = @(Get-WindowsImage -ImagePath $imagePath | Where-Object ImageName -eq $Variables.image_name)
    if ($images.Count -ne 1) { throw 'Exact image_name must identify one image; inspect media with Get-WindowsImage.' }
    $image = Get-WindowsImage -ImagePath $imagePath -Index $images[0].ImageIndex
    $builds = @{ '2019'=17763; '2022'=20348; '2025'=26100 }
    if (([version]$image.Version).Build -ne $builds[$Variables.server_version]) { throw 'ISO image release differs from server_version.' }
    if ($image.EditionId -notmatch ('^Server'+$Variables.edition+'(Eval)?$')) { throw 'ISO edition differs from requested edition.' }
    $expectedType = if ($Variables.installation_type -eq 'Core') { 'Server Core' } else { 'Server' }
    if ($image.InstallationType -ne $expectedType -or $image.Architecture -notin 9,'amd64','x64') { throw 'ISO installation type or architecture is incompatible.' }
    if (@($image.Languages | Where-Object { $_ -match '^en-US' }).Count -eq 0) { throw 'Use English Microsoft media; regional settings remain configurable.' }
    if (-not (Test-Path "$drive\efi\microsoft\boot\efisys.bin")) { throw 'Media lacks Windows UEFI boot image.' }
    if (@(Get-ChildItem "$drive\sources\sxs" -File -Filter '*netfx3*').Count -eq 0) { throw '.NET 3.5 installation payload is missing.' }
} finally { if (-not $wasAttached) { Dismount-DiskImage -ImagePath $iso.FullName | Out-Null } }
$seen = @{}
if ($Variables.ContainsKey('approved_oob_packages')) {
    foreach ($package in $Variables.approved_oob_packages) {
        if ($package.kb -notmatch '^KB[0-9]+$' -or $seen.ContainsKey($package.kb)) { throw 'Offline packages require distinct KB identities.' }
        $seen[$package.kb] = $true
        if ([IO.Path]::GetExtension($package.path) -ne '.msu' -or (Get-FileHash -LiteralPath $package.path -Algorithm SHA256).Hash -ne $package.sha256) { throw "Approved MSU checksum mismatch: $($package.kb)" }
        # MSU container trust is established by the approved hash/provenance;
        # DISM also validates signed servicing payloads inside the guest.
    }
}
Write-Output 'Host, switch, approved ISO, image edition/type, UEFI and feature payload validated.'
