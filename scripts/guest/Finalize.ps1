# Invoked ONLY by the Hyper-V builder's shutdown_command. It starts a SYSTEM
# task so removing the build listener cannot kill generalization.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = 'C:\ProgramData\ImageFactory'
if ((Get-Content "$root\validation.json" -Raw | ConvertFrom-Json).status -ne 'passed') { throw 'Final validation did not pass.' }
$worker = @'
$ErrorActionPreference = 'Stop'
Start-Sleep -Seconds 10
try {
    $root = 'C:\ProgramData\ImageFactory'
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path $key) { throw 'Pending reboot before Sysprep' }
    }
    # All cached answer files are also removed by the cleanup plugin.
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    foreach ($name in 'DefaultPassword', 'DefaultUserName', 'DefaultDomainName', 'AutoLogonCount') { Remove-ItemProperty $winlogon -Name $name -ErrorAction SilentlyContinue }
    Set-ItemProperty $winlogon -Name AutoAdminLogon -Value '0'
    $thumb = (Get-Content "$root\certificate.txt" -Raw).Trim()
    Get-ChildItem WSMan:\localhost\Listener | Remove-Item -Recurse -Force
    Remove-NetFirewallRule -Name ImageFactory-WinRM
    if ($thumb -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Invalid bootstrap certificate identity' }
    Remove-Item -LiteralPath "Cert:\LocalMachine\My\$thumb" -Force
    # Invalidate the build password even if Sysprep later fails. Password never
    # appears in argv, files, environment, task definitions or build logs.
    $bytes = New-Object byte[] 48
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $password = 'aA1!' + [Convert]::ToBase64String($bytes)
    $admin = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }
    $admin | Set-LocalUser -Password (ConvertTo-SecureString $password -AsPlainText -Force)
    $password = $null
    [Array]::Clear($bytes, 0, $bytes.Length)
    Unregister-ScheduledTask -TaskName ImageFactory-Generalize -Confirm:$false
    # Delete only known factory-owned files; preserve Windows servicing logs.
    foreach ($file in 'Finalize.ps1', 'Generalize.ps1', 'certificate.txt', 'oob.json', 'bootstrap-status.json', 'validation.json') {
        Remove-Item -LiteralPath (Join-Path $root $file) -Force -ErrorAction SilentlyContinue
    }
    $sysprep = Start-Process -FilePath C:\Windows\System32\Sysprep\Sysprep.exe -ArgumentList '/generalize /oobe /shutdown /quiet' -Wait -PassThru -WindowStyle Hidden
    if ($sysprep.ExitCode -ne 0) { throw "Sysprep failed: $($sysprep.ExitCode)" }
} catch {
    # Never perform a fallback shutdown: the builder must time out on failure.
    $_ | Out-String | Set-Content C:\ProgramData\ImageFactory\generalization-error.txt
    exit 1
}
'@
$path = "$root\Generalize.ps1"
$worker | Set-Content -LiteralPath $path -Encoding UTF8
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $path"
$principal = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 25)
Register-ScheduledTask -TaskName ImageFactory-Generalize -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName ImageFactory-Generalize
