$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = 'C:\ProgramData\ImageFactory'
$problems = [System.Collections.Generic.List[string]]::new()
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$builds = @{ '2019' = 17763; '2022' = 20348; '2025' = 26100 }
if ($os.ProductType -ne 3 -or [int]$os.BuildNumber -ne $builds[$env:FACTORY_SERVER]) { $problems.Add('Wrong Windows Server build/product type') }
if ($cv.EditionID -notmatch ('^Server' + $env:FACTORY_EDITION + '(Eval)?$')) { $problems.Add('Wrong edition') }
$expectedType = if ($env:FACTORY_INSTALLATION -eq 'Core') { 'Server Core' } else { 'Server' }
if ($cv.InstallationType -ne $expectedType) { $problems.Add('Wrong installation type') }
$features = @(Get-WindowsFeature | Select-Object Name, InstallState)
if ((Get-WindowsFeature NET-Framework-Core).InstallState -ne 'Installed') { $problems.Add('.NET 3.5 is not installed') }
if (@(Get-WindowsFeature PowerShell-V2 -ErrorAction SilentlyContinue | Where-Object Installed).Count) { $problems.Add('PowerShell 2.0 remains installed') }
if ($PSVersionTable.PSVersion -lt [version]'5.1' -or -not [Environment]::Is64BitProcess) { $problems.Add('Native PowerShell 5.1 unavailable') }
$reboot = @()
foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
    if (Test-Path $key) { $reboot += $key }
}
$session = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
if ($session.PSObject.Properties['PendingFileRenameOperations'] -and $session.PendingFileRenameOperations) { $reboot += 'PendingFileRenameOperations' }
if (Test-Path C:\Windows\WinSxS\pending.xml) { $reboot += 'pending.xml' }
$packages = @(Get-WindowsPackage -Online)
if (@($packages | Where-Object PackageState -Match 'Pending').Count) { $reboot += 'Pending DISM package' }
if ($reboot.Count) { $problems.Add('Pending restart remains') }
if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) { $problems.Add('Windows Update requires reboot') }
if ((New-Object -ComObject Microsoft.Update.Installer).IsBusy) { $problems.Add('Windows Update installer is busy') }
$wu = New-Object -ComObject Microsoft.Update.Session
$searcher = $wu.CreateUpdateSearcher()
$remaining = $searcher.Search($env:FACTORY_SEARCH)
if ($remaining.ResultCode -ne 2) { throw "Final update search did not succeed: $($remaining.ResultCode)" }
$required = @($remaining.Updates | Where-Object { $_.Title -notmatch 'Preview' })
if ($required.Count) { $problems.Add('Required updates remain applicable') }
$historyCount = $searcher.GetTotalHistoryCount()
$history = @()
if ($historyCount -gt 0) { $history = @($searcher.QueryHistory(0, $historyCount) | Select-Object Title, Date, Operation, ResultCode, HResult) }
$approved = @(Get-Content "$root\oob.json" -Raw | ConvertFrom-Json)
$hotfixes = @(Get-HotFix | Select-Object HotFixID, Description, InstalledOn)
foreach ($p in $approved) {
    # Package supersedence can remove an older KB from QFE; retain DISM evidence.
    if (-not @($hotfixes | Where-Object HotFixID -eq $p.kb).Count -and -not @($packages | Where-Object { $_.PackageName -match [regex]::Escape($p.kb) -and $_.PackageState -in 'Installed', 'Superseded' }).Count) { $problems.Add("Approved package lacks installed/superseded evidence: $($p.kb)") }
}
if ((Get-Service WinRM).Status -ne 'Running') { $problems.Add('WinRM unavailable') }
if (-not (Confirm-SecureBootUEFI)) { $problems.Add('Secure Boot disabled') }
if ((Get-Disk -Number 0).PartitionStyle -ne 'GPT') { $problems.Add('System disk is not GPT') }
$health = Repair-WindowsImage -Online -ScanHealth
if ($health.ImageHealthState -ne 'Healthy') { $problems.Add('Component store is not healthy') }
@{
    schema_version = 1; status = $(if ($problems.Count) { 'failed' } else { 'passed' })
    checked_at = [DateTime]::UtcNow.ToString('o'); errors = @($problems.ToArray())
    server_version = $env:FACTORY_SERVER; edition = $cv.EditionID; installation_type = $cv.InstallationType
    windows_build = "$($os.Version).$($cv.UBR)"; features = $features
    installed_updates = $hotfixes; packages = @($packages | Select-Object PackageName, PackageState)
    update_history = $history; remaining_required_updates = @($required | ForEach-Object Title)
    pending_reboot = $reboot; component_health = [string]$health.ImageHealthState
} | ConvertTo-Json -Depth 12 | Set-Content "$root\validation.json" -Encoding UTF8
if ($problems.Count) { throw ($problems -join '; ') }
