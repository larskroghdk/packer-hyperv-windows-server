[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Read sibling repositories; build output and plugin inventory stay here.
$workspace = Split-Path $PSScriptRoot -Parent
$pluginRoot = Join-Path $workspace '.validation\plugins'
$binaryRoot = Join-Path $workspace '.validation\bin'
New-Item -ItemType Directory -Path $pluginRoot,$binaryRoot -Force | Out-Null
$env:PACKER_PLUGIN_PATH = $pluginRoot
$env:GOCACHE = Join-Path $workspace '.validation\go-cache'
$provenance = @()
foreach ($name in 'features','optimize','harden','cleanup') {
    $repo = Join-Path $RepositoryRoot "packer-plugin-windows-$name"
    if (-not (Test-Path (Join-Path $repo 'go.mod'))) { throw "Missing plugin source: $repo" }
    $binary = Join-Path $binaryRoot "packer-plugin-windows-$name.exe"
    Push-Location $repo
    try {
        $commit = (& git rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
        $dirty = @(& git status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source status.' }
        & go build -trimpath -ldflags '-X main.versionPrerelease=' -o $binary .
        if ($LASTEXITCODE -ne 0) { throw "Plugin compilation failed: $name" }
    } finally { Pop-Location }
    & packer plugins install --path $binary "github.com/larskroghdk/windows-$name"
    if ($LASTEXITCODE -ne 0) { throw "Plugin installation failed: $name" }
    $provenance += @{ plugin="windows-$name"; source=$repo; commit=$commit; dirty=[bool]$dirty.Count; binary_sha256=(Get-FileHash $binary).Hash }
}
$provenance | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $workspace '.validation\plugin-provenance.json') -Encoding UTF8
Write-Output "Local plugins installed. Set PACKER_PLUGIN_PATH=$pluginRoot in subsequent shells, then run packer init ."
