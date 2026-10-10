$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

$repository = Split-Path -Parent $PSScriptRoot
$binDirectory = Join-Path $repository 'bin'
$launcher = Join-Path $binDirectory 'ffs.cmd'
$originalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$originalMachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testDirectory = Join-Path $tempRoot ('ffs installer test ' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testDirectory | Out-Null

Push-Location -LiteralPath $testDirectory
try {
    Set-Content -LiteralPath 'sample.txt' -Value 'ffs installer fixture'
    New-Item -ItemType Directory -Path 'node_modules' | Out-Null
    Set-Content -LiteralPath 'node_modules\ignored.txt' -Value 'ignored'
    $relativeInstaller = Resolve-Path -LiteralPath (Join-Path $repository 'install.ps1') -Relative
    $relativeLauncher = Resolve-Path -LiteralPath $launcher -Relative

    & $relativeInstaller
    Assert ((Get-Location).Path -eq $testDirectory) 'The installer changed the caller directory.'
    $installedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert ($installedUserPath.StartsWith([string]$originalUserPath, [StringComparison]::Ordinal)) 'Existing user PATH content was changed.'
    Assert ([Environment]::GetEnvironmentVariable('Path', 'Machine') -ceq $originalMachinePath) 'Machine PATH was changed.'
    Assert ((Get-Command ffs -ErrorAction Stop).Source -ieq $launcher) 'ffs does not resolve to this checkout on PATH.'

    $relativeHelp = & $relativeLauncher --help
    Assert ($LASTEXITCODE -eq 0) 'The launcher failed when invoked by relative path outside the repository.'
    Assert (($relativeHelp -join "`n") -match 'dotnet test') 'The launcher did not execute the current CLI.'

    $listing = @(ffs find)
    Assert ($LASTEXITCODE -eq 0) 'ffs find failed outside the repository.'
    Assert ($listing -contains './sample.txt') 'ffs find did not use the caller directory.'
    Assert (($listing -join "`n") -notmatch 'node_modules') 'ffs find did not skip dependency directories.'

    $lookup = ffs which node
    Assert ($LASTEXITCODE -eq 0) 'Argument forwarding failed for ffs which node.'
    Assert (($lookup -join "`n") -match 'node') 'Command lookup produced no Node.js result.'

    & $relativeInstaller
    Assert ([Environment]::GetEnvironmentVariable('Path', 'User') -ceq $installedUserPath) 'Reinstallation changed or duplicated user PATH entries.'
    $matchingProcessEntries = @($env:Path -split ';' | Where-Object {
        [Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"')).TrimEnd('\', '/') -ieq $binDirectory
    })
    Assert ($matchingProcessEntries.Count -eq 1) 'Reinstallation duplicated the process PATH entry.'
    Assert ((Get-Location).Path -eq $testDirectory) 'Reinstallation changed the caller directory.'

    Write-Host 'Installer integration tests passed.'
} finally {
    Pop-Location
    $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
    if (-not $resolvedTestDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a test directory outside $tempRoot."
    }
    Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
}
