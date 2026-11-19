[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('2019','2022','2025')][string]$Version,[Parameter(Mandatory)][string]$SettingsPath,[switch]$AuthorizeLiveBuild,[string]$ExternalStorage)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeLiveBuild) { throw 'Live integration creates and disposes an isolated VM and consumes storage. Supply -AuthorizeLiveBuild explicitly on a dedicated host.' }
& (Join-Path $PSScriptRoot '..\..\scripts\Build.ps1') -Version $Version -SettingsPath $SettingsPath -Build -ExternalStorage $ExternalStorage
