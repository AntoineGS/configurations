[CmdletBinding()]
param(
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = 'C:\Gits\shell-picker'

try {
  if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    exit 1
  }

  $go = Get-Command go.exe -CommandType Application -ErrorAction Stop
  $gopath = (& $go.Source env GOPATH 2>$null | Out-String).Trim()
  $goExitCode = $LASTEXITCODE
  if ($goExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($gopath)) {
    exit 1
  }

  $binary = Join-Path $gopath 'bin\shell-picker.exe'
  if ($Check) {
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
      exit 1
    }

    $git = Get-Command git.exe -CommandType Application -ErrorAction Stop
    $head = (& $git.Source -C $source rev-parse HEAD 2>$null | Out-String).Trim()
    $gitExitCode = $LASTEXITCODE
    if ($gitExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
      exit 1
    }

    $version = (& $binary version 2>$null | Out-String).Trim()
    $versionExitCode = $LASTEXITCODE
    if ($versionExitCode -ne 0 -or $version -ne 'shell-picker dev') {
      exit 1
    }

    $metadata = & $go.Source version -m $binary 2>$null | Out-String
    $metadataExitCode = $LASTEXITCODE
    if ($metadataExitCode -ne 0 -or -not $metadata.Contains(('vcs.revision=' + $head))) {
      exit 1
    }
    exit 0
  }

  Push-Location -LiteralPath $source
  try {
    & $go.Source install -trimpath ./cmd/shell-picker
    $installExitCode = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }
  if ($installExitCode -ne 0) {
    exit $installExitCode
  }
  if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    exit 1
  }
  exit 0
}
catch {
  exit 1
}
