# Exercise the release gate and checksum with synthetic host-side evidence.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Join-Path $PSScriptRoot '..\..')
$dir = Join-Path $PWD ('.validation\manifest-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Write-Fixture([string]$Name,[object]$Value) { $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $dir $Name) -Encoding UTF8 }
Write-Fixture 'validation.json' @{ status='passed'; windows_build='10.0.20348.1'; features=@(@{Name='NET-Framework-Core';InstallState='Installed'}); installed_updates=@(); packages=@(); update_history=@(); remaining_required_updates=@() }
Write-Fixture 'offline-validation.json' @{status='passed';image_state='IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE'}
Write-Fixture 'packer-manifest.json' @{builds=@(@{custom_data=@{image_id='test-image-1'}})}
Write-Fixture 'cleanup.json' @{status='success'}
Write-Fixture 'optimization.json' @{summary=@{failed=0;pending=0}}
Write-Fixture 'hardening.json' @{summary=@{failed=0;pending=0}}
Write-Fixture 'optimization-validation.json' @{summary=@{failed=0;pending=0}}
Write-Fixture 'hardening-validation.json' @{summary=@{failed=0;pending=0}}
foreach ($name in 'features-remove.json','features-netfx.json') { Write-Fixture $name @{validation=@{passed=$true}} }
$disk = Join-Path $dir 'inert-fixture.vhdx'
'Inert checksum fixture; not a virtual disk.' | Set-Content -LiteralPath $disk
$vars = @{image_version='1';server_version='2022';edition='Datacenter';installation_type='Core';approved_oob_packages=@();iso_checksum=('sha256:' + ('a'*64))}
& ./scripts/New-Manifest.ps1 -Variables $vars -ReportDirectory $dir -Vhdx $disk -StartedAt ([DateTime]::UtcNow.AddSeconds(-1))
$manifest = Get-Content (Join-Path $dir 'test-image-1.manifest.json') -Raw | ConvertFrom-Json
if ($manifest.sha256 -ne (Get-FileHash $disk).Hash.ToLowerInvariant() -or $manifest.final_validation.status -ne 'passed' -or $manifest.duration_seconds -lt 0) { throw 'Manifest output/checksum contract failed.' }
Remove-Item -LiteralPath (Join-Path $dir 'test-image-1.manifest.json')
Write-Fixture 'offline-validation.json' @{status='failed'}
$rejected = $false
try { & ./scripts/New-Manifest.ps1 -Variables $vars -ReportDirectory $dir -Vhdx $disk -StartedAt ([DateTime]::UtcNow) } catch { $rejected = $true }
if (-not $rejected -or (Test-Path (Join-Path $dir 'test-image-1.manifest.json'))) { throw 'Failed offline validation must not issue a release manifest.' }
Write-Fixture 'offline-validation.json' @{status='passed'}
Write-Fixture 'hardening-validation.json' @{summary=@{failed=0;pending=1}}
$rejected = $false
try { & ./scripts/New-Manifest.ps1 -Variables $vars -ReportDirectory $dir -Vhdx $disk -StartedAt ([DateTime]::UtcNow) } catch { $rejected = $true }
if (-not $rejected -or (Test-Path (Join-Path $dir 'test-image-1.manifest.json'))) { throw 'Pending post-update hardening must block release.' }
Write-Output 'Passed manifest serialization, checksum and failed-release rejection checks.'
