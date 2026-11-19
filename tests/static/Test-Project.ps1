[CmdletBinding()]
param([switch]$SkipPacker)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Join-Path $PSScriptRoot '..\..')
$checks = 0
function Assert-Check([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message }; $script:checks++ }
foreach ($script in Get-ChildItem scripts,tests -Filter '*.ps1' -Recurse) {
    $parseErrors = $null; $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
    Assert-Check ($parseErrors.Count -eq 0) ("PowerShell parse errors in " + $script.FullName + ': ' + ($parseErrors -join '; '))
}
$build = Get-Content build.pkr.hcl -Raw
$stagePatterns = @('script\s*=\s*"scripts/guest/Prepare.ps1"','remove\s*=\s*\["PowerShell-V2"\]','install\s*=\s*\["NET-Framework-Core"\]','provisioner "windows-optimize"','provisioner "windows-harden"','provisioner "windows-update"','provisioner "windows-cleanup"','script\s*=\s*"scripts/guest/Validate.ps1"','source\s*=\s*"scripts/guest/Finalize.ps1"')
$last = -1
foreach ($pattern in $stagePatterns) { $match = [regex]::Match($build,$pattern); Assert-Check ($match.Success -and $match.Index -gt $last) "Missing or misordered stage: $pattern"; $last = $match.Index }
Assert-Check ($build -match 'sysprep\s*=\s*false') 'Cleanup Sysprep must remain disabled on Hyper-V.'
$source = Get-Content sources.pkr.hcl -Raw
foreach ($pattern in 'generation\s*=\s*2','enable_secure_boot\s*=\s*true','secure_boot_template\s*=\s*"MicrosoftWindows"','winrm_use_ssl\s*=\s*true','winrm_use_ntlm\s*=\s*true','skip_export\s*=\s*true','shutdown_command\s*=.*Finalize.ps1') { Assert-Check ($source -match $pattern) "Builder invariant missing: $pattern" }
$xml = Get-Content http/autounattend/Autounattend.xml.pkrtpl -Raw
foreach ($pair in @{keyboard='0409:00000409';locale='en-US';time_zone='Romance Standard Time';image_name='Windows Server &amp; test';password='Aa1!&lt;&gt;&amp;&quot;&apos;test'}.GetEnumerator()) { $xml = $xml.Replace('${'+$pair.Key+'}', $pair.Value) }
$document = [xml]$xml
$ns = [Xml.XmlNamespaceManager]::new($document.NameTable); $ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
Assert-Check ($document.SelectSingleNode('//u:AdministratorPassword/u:Value',$ns).InnerText -eq 'Aa1!<>&"''test') 'XML credential escaping failed.'
Assert-Check ($document.SelectSingleNode('//u:InstallTo/u:PartitionID',$ns).InnerText -eq '3') 'GPT target partition mismatch.'
Assert-Check ($document.SelectNodes('//u:AutoLogon',$ns).Count -eq 0) 'Autologon credentials are prohibited.'
$finalizer = Get-Content scripts/guest/Finalize.ps1 -Raw
$bootstrap = Get-Content scripts/bootstrap/Bootstrap.ps1 -Raw
$rootName = [regex]::Match($bootstrap, 'ProgramData\\([A-Za-z]+)').Groups[1].Value
Assert-Check ($rootName.Length -gt 0 -and $source.Contains('ProgramData\\' + $rootName + '\\')) 'Bootstrap and builder shutdown staging directories differ.'
foreach ($path in 'scripts/guest/Prepare.ps1','scripts/guest/Validate.ps1','scripts/guest/Finalize.ps1','scripts/Test-Image.ps1') {
    Assert-Check ((Get-Content $path -Raw).Contains('ProgramData\' + $rootName)) "Bootstrap staging directory differs from $path"
}
$rule = [regex]::Match($bootstrap, 'New-NetFirewallRule -Name ([A-Za-z-]+)').Groups[1].Value
Assert-Check ($rule.Length -gt 0 -and $finalizer.Contains('Remove-NetFirewallRule -Name ' + $rule)) 'Bootstrap firewall rule is not removed by finalization.'
Assert-Check ($finalizer -match '/generalize /oobe /shutdown' -and $finalizer -notmatch 'Stop-Computer|shutdown.exe') 'Generalization must own shutdown without a fallback.'
$parseErrors = $null; $tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($finalizer,[ref]$tokens,[ref]$parseErrors)
$assignment = $ast.Find({param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$worker'}, $true)
$worker = $assignment.Right.Find({param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst]}, $true).Value
[System.Management.Automation.Language.Parser]::ParseInput($worker,[ref]$tokens,[ref]$parseErrors) | Out-Null
Assert-Check ($parseErrors.Count -eq 0) 'Embedded SYSTEM generalization script has PowerShell syntax errors.'
foreach ($md in Get-ChildItem . -Filter '*.md' -Recurse | Where-Object FullName -notmatch '\\(\.git|\.validation)\\') {
    foreach ($match in [regex]::Matches((Get-Content $md.FullName -Raw),'\[[^\]]*\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Split('#')[0]
        if ($target -and $target -notmatch '^https?://|^mailto:') { Assert-Check (Test-Path -LiteralPath (Join-Path $md.DirectoryName $target)) "Broken documentation link in $($md.Name): $target" }
    }
}
if (-not $SkipPacker) {
    & "$PSScriptRoot/Test-Manifest.ps1"
    & packer init .
    if ($LASTEXITCODE -ne 0) { throw 'packer init failed; install published releases or use scripts/Install-LocalPlugins.ps1.' }
    & packer fmt -check -recursive .
    Assert-Check ($LASTEXITCODE -eq 0) 'Packer formatting check failed.'
    $oldPassword = $env:PKR_VAR_administrator_password
    try {
        $env:PKR_VAR_administrator_password = 'StaticOnly-Aa1!<>&'
        foreach ($version in '2019','2022','2025') {
            foreach ($type in 'Core','Desktop') {
                & packer validate "-var-file=config/windows-server-$version.pkrvars.hcl" '-var-file=tests/static/validation.pkrvars.json' "-var=installation_type=$type" .
                Assert-Check ($LASTEXITCODE -eq 0) "Packer validation failed for $version $type"
            }
        }
        foreach ($bad in 'server_version=2016','edition=Enterprise','iso_checksum=none','cpus=0','build_id=existing-vm') {
            $result = & packer validate '-var-file=config/windows-server-2022.pkrvars.hcl' '-var-file=tests/static/validation.pkrvars.json' "-var=$bad" . 2>&1
            Assert-Check ($LASTEXITCODE -ne 0) "Invalid configuration unexpectedly accepted: $bad"
        }
        # Expand the optional dynamic package/restart blocks during validation.
        # This is inert test data; neither an ISO nor an MSU is executed.
        New-Item -ItemType Directory .validation -Force | Out-Null
        $fixture = Join-Path $PWD '.validation\schema-only.msu'
        'Inert schema-validation fixture. Not installation media.' | Set-Content $fixture
        $override = Join-Path $PWD '.validation\oob-validation.pkrvars.json'
        @{ approved_oob_packages=@(@{path=$fixture; kb='KB1234567'; sha256=(Get-FileHash $fixture).Hash}) } | ConvertTo-Json -Depth 6 | Set-Content $override
        & packer validate '-var-file=config/windows-server-2025.pkrvars.hcl' '-var-file=tests/static/validation.pkrvars.json' "-var-file=$override" .
        Assert-Check ($LASTEXITCODE -eq 0) 'Optional offline package/restart schema validation failed.'
    } finally { $env:PKR_VAR_administrator_password = $oldPassword }
}
Write-Output "Passed $checks static checks. No VMs were created."
