# Runs once as SYSTEM during specialize. No credentials are passed to a shell.
$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$root = "$env:ProgramData\ImageFactory"
$options = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bootstrap.json') -Raw | ConvertFrom-Json
$media = @(Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\sources\sxs") -and ((Test-Path "$($_.DriveLetter):\sources\install.wim") -or (Test-Path "$($_.DriveLetter):\sources\install.esd")) })
if ($media.Count -ne 1) {
    throw 'Expected exactly one Windows installation DVD with sources\sxs.'
}
$source = "$($media[0].DriveLetter):\sources\sxs"
if (@(Get-ChildItem -LiteralPath $source -File -Filter '*netfx3*').Count -eq 0) {
    throw 'Installation media lacks a .NET 3.5 payload.'
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$payload = [string]$options.netfx_source
if ($payload -notmatch '^C:\\ProgramData\\PackerCleanup\\Staging\\[A-Za-z0-9_-]+(\\[A-Za-z0-9_-]+)*$') { throw 'Invalid feature payload staging directory.' }
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Copy-Item -Path "$source\*" -Destination $payload -Recurse -Force
Enable-PSRemoting -SkipNetworkProfileCheck -Force
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTP' } | Remove-Item -Recurse -Force
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true
$certificate = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddDays(7) -KeyLength 2048 -HashAlgorithm SHA256
New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{ Transport = 'HTTPS'; Address = '*' } -ValueSet @{ Hostname = $env:COMPUTERNAME; CertificateThumbprint = $certificate.Thumbprint; Port = [string]$options.port } | Out-Null
New-NetFirewallRule -Name ImageFactory-WinRM -DisplayName 'Temporary Packer HTTPS WinRM' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $options.port -RemoteAddress $options.allowed_address -Profile Any | Out-Null
$certificate.Thumbprint | Set-Content -LiteralPath "$root\certificate.txt"
Set-Service WinRM -StartupType Automatic
Restart-Service WinRM
$deadline = (Get-Date).AddMinutes(5)
do {
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' })
    if ($addresses.Count) {
        break
    }
    Start-Sleep -Seconds 5
} while ((Get-Date) -lt $deadline)
if (-not $addresses.Count) {
    throw 'No routable DHCP IPv4 address within five minutes.'
}
@{ bootstrap = 'passed'; completed_at = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content "$root\bootstrap-status.json"
