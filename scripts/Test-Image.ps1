[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$vhd = Get-VHD -Path (Resolve-Path -LiteralPath $Path).Path
if ($vhd.Attached -or $vhd.VhdType -eq 'Differencing' -or $vhd.ParentPath) { throw 'Output must be a detached standalone VHDX.' }
$mount = $null
$hive = 'ImageFactory_' + [guid]::NewGuid().ToString('N')
$loaded = $false
$access = $null
$hiveCopy = $null
try {
    $mount = Mount-VHD -Path $vhd.Path -ReadOnly -NoDriveLetter -Passthru
    $disk = $mount | Get-Disk
    if ($disk.PartitionStyle -ne 'GPT') { throw 'Captured image is not GPT.' }
    $partitions = @($disk | Get-Partition)
    $windows = @($partitions | Where-Object { $_.Type -eq 'Basic' })
    if ($windows.Count -ne 1) { throw 'Expected exactly one Windows data partition.' }
    $access = (Join-Path ([IO.Path]::GetTempPath()) $hive) + '\'
    New-Item -ItemType Directory -Path $access | Out-Null
    $windows[0] | Add-PartitionAccessPath -AccessPath $access
    # Registry hive loading may require write access. Copy the hive and its
    # transaction logs to host scratch; never modify the captured disk.
    $hiveCopy = Join-Path ([IO.Path]::GetTempPath()) ($hive + '_hive')
    New-Item -ItemType Directory -Path $hiveCopy | Out-Null
    foreach ($name in 'SOFTWARE','SOFTWARE.LOG1','SOFTWARE.LOG2') {
        $source = Join-Path $access "Windows\System32\config\$name"
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $hiveCopy }
    }
    & reg.exe load "HKLM\$hive" (Join-Path $hiveCopy 'SOFTWARE') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not read captured SOFTWARE hive.' }
    $loaded = $true
    $state = (Get-ItemProperty "Registry::HKEY_LOCAL_MACHINE\$hive\Microsoft\Windows\CurrentVersion\Setup\State").ImageState
    if ($state -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { throw "Sysprep state is not generalized for OOBE: $state" }
    foreach ($file in 'Windows\Panther\Unattend.xml','Windows\Panther\Unattend\Unattend.xml','Windows\System32\Sysprep\Unattend.xml','ProgramData\ImageFactory\certificate.txt','ProgramData\ImageFactory\Finalize.ps1','ProgramData\ImageFactory\Generalize.ps1','ProgramData\ImageFactory\generalization-error.txt') {
        if (Test-Path -LiteralPath (Join-Path $access $file)) { throw "Build artifact remains in captured image: $file" }
    }
    @{ schema_version=1; status='passed'; image_state=$state; checked_at=[DateTime]::UtcNow.ToString('o'); standalone=$true; gpt=$true } | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
} finally {
    if ($loaded) { [GC]::Collect(); [GC]::WaitForPendingFinalizers(); & reg.exe unload "HKLM\$hive" | Out-Null }
    if ($access -and $mount) { $windows[0] | Remove-PartitionAccessPath -AccessPath $access -ErrorAction SilentlyContinue }
    if ($mount) { Dismount-VHD -Path $vhd.Path }
    if ($access -and (Test-Path -LiteralPath $access)) { Remove-Item -LiteralPath $access -ErrorAction SilentlyContinue }
    if ($hiveCopy -and (Test-Path -LiteralPath $hiveCopy)) {
        # Remove only the explicitly copied files; keep scratch if unload failed.
        foreach ($name in 'SOFTWARE','SOFTWARE.LOG1','SOFTWARE.LOG2') { Remove-Item -LiteralPath (Join-Path $hiveCopy $name) -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $hiveCopy -ErrorAction SilentlyContinue
    }
}
