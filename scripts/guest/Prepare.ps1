$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$builds = @{ '2019' = 17763; '2022' = 20348; '2025' = 26100 }
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
if ($os.ProductType -ne 3 -or [int]$os.BuildNumber -ne $builds[$env:FACTORY_SERVER]) { throw 'Installed OS does not match the selected Windows Server release.' }
if ($cv.EditionID -notmatch ('^Server' + $env:FACTORY_EDITION + '(Eval)?$')) { throw 'Installed edition differs from requested edition.' }
$expectedType = if ($env:FACTORY_INSTALLATION -eq 'Core') { 'Server Core' } else { 'Server' }
if ($cv.InstallationType -ne $expectedType) { throw 'Installed Core/Desktop type differs from the request.' }
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) { throw 'Native Windows PowerShell 5.1 is required.' }
if ((Get-Content 'C:\ProgramData\ImageFactory\bootstrap-status.json' -Raw | ConvertFrom-Json).bootstrap -ne 'passed') { throw 'Bootstrap did not complete.' }
if (-not (Confirm-SecureBootUEFI)) { throw 'Secure Boot is not enabled.' }
if ((Get-Disk -Number 0).PartitionStyle -ne 'GPT') { throw 'System disk must be GPT.' }
if (-not (Test-Path -LiteralPath $env:FACTORY_NETFX_SOURCE)) { throw 'Validated feature payload is missing.' }
