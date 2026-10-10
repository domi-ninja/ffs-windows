<#
.SYNOPSIS
Builds ffs and adds this checkout's bin directory to the current user's PATH.
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This installer is only available on Windows.'
}

$node = Get-Command node.exe -ErrorAction Stop
$nodeVersion = & $node.Source --version
if ($LASTEXITCODE -ne 0 -or ([version]$nodeVersion.TrimStart('v')).Major -lt 18) {
    throw 'ffs requires Node.js 18 or newer on PATH.'
}

$packageManager = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
if ($packageManager) {
    $installArguments = @('install', '--frozen-lockfile', '--prod=false')
} else {
    $packageManager = Get-Command npm.cmd -ErrorAction Stop
    $installArguments = @('install', '--include=dev', '--no-package-lock')
}

Push-Location -LiteralPath $PSScriptRoot
try {
    & $packageManager.Source @installArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency installation failed with exit code $LASTEXITCODE."
    }

    & $packageManager.Source run build
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE."
    }

    # Verify the build and native dependencies before changing PATH.
    & $node.Source (Join-Path $PSScriptRoot 'dist\ffs.js') --help
    if ($LASTEXITCODE -ne 0) {
        throw "ffs verification failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

$binDirectory = Join-Path $PSScriptRoot 'bin'

function Test-PathEntry([string]$pathValue, [string]$directory) {
    foreach ($entry in ($pathValue -split ';')) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\', '/')
        if ($expanded -ieq $directory.TrimEnd('\', '/')) {
            return $true
        }
    }
    return $false
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (Test-PathEntry $userPath $binDirectory)) {
    $updatedPath = if ([string]::IsNullOrEmpty($userPath)) {
        $binDirectory
    } elseif ($userPath.EndsWith(';')) {
        $userPath + $binDirectory
    } else {
        $userPath + ';' + $binDirectory
    }
    [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')

    if (-not ('FfsInstallerEnvironment' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FfsInstallerEnvironment {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
}
'@
    }
    $broadcastResult = [UIntPtr]::Zero
    [void][FfsInstallerEnvironment]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment',
        0x0002, 5000, [ref]$broadcastResult)
}

if (-not (Test-PathEntry $env:Path $binDirectory)) {
    $env:Path += ';' + $binDirectory
}

Write-Host "Installed ffs from $PSScriptRoot. Keep this checkout in place."
Write-Host 'Run ffs --help. Open a new terminal if an existing terminal cannot find ffs.'
