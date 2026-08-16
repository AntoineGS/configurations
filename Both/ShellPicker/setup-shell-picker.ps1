param(
    [switch]$Check,
    [switch]$Apply,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = if ([string]::IsNullOrWhiteSpace($env:SHELL_PICKER_SOURCE_DIR)) {
    'C:\Gits\shell-picker'
} else {
    $env:SHELL_PICKER_SOURCE_DIR
}

function Get-GoPath {
    $gopath = (& go.exe env GOPATH 2>$null | Out-String).Trim()
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($gopath)) {
        throw 'go env GOPATH failed'
    }
    return $gopath
}

function Test-Binary {
    try {
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $false }
        $null = Get-Command go.exe -ErrorAction Stop
        $null = Get-Command git.exe -ErrorAction Stop

        $gopath = Get-GoPath
        $binary = [IO.Path]::Combine($gopath, 'bin', 'shell-picker.exe')
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { return $false }

        $head = (& git.exe -C $source rev-parse HEAD 2>$null | Out-String).Trim()
        $gitExitCode = $LASTEXITCODE
        if ($gitExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($head)) { return $false }

        $version = (& $binary version 2>$null | Out-String).Trim()
        $versionExitCode = $LASTEXITCODE
        if ($versionExitCode -ne 0 -or $version -ne 'shell-picker dev') { return $false }

        $metadata = & go.exe version -m $binary 2>$null | Out-String
        $metadataExitCode = $LASTEXITCODE
        return $metadataExitCode -eq 0 -and $metadata.Contains("vcs.revision=$head")
    } catch {
        return $false
    }
}

function Apply-Binary {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { exit 1 }

    try {
        $null = Get-Command go.exe -ErrorAction Stop
        Push-Location -LiteralPath $source
        try {
            & go.exe install -trimpath ./cmd/shell-picker
            $installExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($installExitCode -ne 0) { exit $installExitCode }

        $gopath = Get-GoPath
        $binary = [IO.Path]::Combine($gopath, 'bin', 'shell-picker.exe')
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { exit 1 }
    } catch {
        exit 1
    }
}

$selectedCount = @(
    if ($Check) { 'check' }
    if ($Apply) { 'apply' }
    if ($Help) { 'help' }
).Count
if ($selectedCount -ne 1) {
    [Console]::Error.WriteLine("Usage: $([IO.Path]::GetFileName($PSCommandPath)) -Check|-Apply|-Help")
    exit 2
}

if ($Check) {
        if (Test-Binary) { exit 0 }
        exit 1
}
if ($Apply) {
        Apply-Binary
        exit 0
}
if ($Help) {
        Write-Output "Usage: $([IO.Path]::GetFileName($PSCommandPath)) -Check|-Apply|-Help"
        exit 0
}
