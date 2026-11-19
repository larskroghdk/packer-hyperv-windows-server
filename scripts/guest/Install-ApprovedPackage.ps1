# Packer windows-restart owns this command and the following reconnect. The
# SYSTEM task avoids Windows Update Agent restrictions on remote sessions.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^KB[0-9]+$')][string]$KB,[Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$Sha256)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$path = "C:\ProgramData\PackerCleanup\Staging\$KB.msu"
if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Sha256) { throw 'Approved package checksum mismatch inside guest.' }
$task = "ImageFactory-$KB"
$action = New-ScheduledTaskAction -Execute 'wusa.exe' -Argument "$path /quiet /norestart"
$principal = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 90)
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
try {
    Start-ScheduledTask -TaskName $task
    $deadline = (Get-Date).AddMinutes(95)
    do {
        Start-Sleep -Seconds 3
        $state = (Get-ScheduledTask -TaskName $task).State
        $info = Get-ScheduledTaskInfo -TaskName $task
        $completed = $state -ne 'Running' -and $info.LastRunTime.Year -gt 2000 -and $info.LastTaskResult -ne 267009
    } while (-not $completed -and (Get-Date) -lt $deadline)
    if (-not $completed) { throw "Approved update $KB exceeded its task deadline." }
    # WUSA: success, success/reboot required, and already installed.
    if ($info.LastTaskResult -notin 0,3010,2359302) { throw "WUSA failed for ${KB}: $($info.LastTaskResult). Check checkpoint prerequisites and servicing logs." }
    Remove-Item -LiteralPath $path -Force
} finally { Unregister-ScheduledTask -TaskName $task -Confirm:$false }
# This is the restart_command of windows-restart, never an independent reboot.
& shutdown.exe /r /t 5 /f /c 'Packer approved offline update'
if ($LASTEXITCODE -ne 0) { throw 'Could not initiate package restart.' }
