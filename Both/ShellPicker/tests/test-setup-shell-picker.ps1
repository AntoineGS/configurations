Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '../setup-shell-picker.ps1'
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('shell-picker-' + [guid]::NewGuid().ToString('N'))
$stubDir = Join-Path $tmpDir 'bin'
$sourceDir = Join-Path $tmpDir 'source'
$goPath = Join-Path $tmpDir 'gopath'
$goBin = Join-Path $goPath 'bin'
$commandLog = Join-Path $tmpDir 'commands.log'
$oldPath = $env:PATH

function Fail([string]$Message) {
    [Console]::Error.WriteLine("FAIL: $Message")
    exit 1
}

function Invoke-Setup([string]$Command) {
    & $pwsh -NoProfile -NonInteractive -File $script $Command 2>&1 | Out-Null
    return $LASTEXITCODE
}

try {
    $pwsh = (Get-Command pwsh).Source
    New-Item -ItemType Directory -Path $stubDir, $sourceDir, $goBin -Force | Out-Null
    Set-Content -LiteralPath $commandLog -Value '' -NoNewline
    @'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'git %s\n' "$*" >> "$COMMAND_LOG"
[[ -d "${2:-}" ]] || exit 1
[[ "${1:-}" == -C && "${3:-}" == rev-parse && "${4:-}" == HEAD ]] || exit 2
printf '%s\n' "${GIT_HEAD:?}"
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'git.exe')
    @'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'go %s\n' "$*" >> "$COMMAND_LOG"
if [[ "${1:-}" == env && "${2:-}" == GOPATH ]]; then
    printf '%s\n' "${GO_GOPATH:?}"
    exit 0
fi
if [[ "${1:-}" == version && "${2:-}" == -m ]]; then
    printf 'path example\nvcs.revision=%s\n' "${GIT_HEAD:?}"
    exit 0
fi
if [[ "${1:-}" == install ]]; then
    mkdir -p -- "${GO_GOPATH:?}/bin"
    printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == version ]] && printf "shell-picker dev\n"' > "${GO_GOPATH}/bin/shell-picker.exe"
    chmod +x -- "${GO_GOPATH}/bin/shell-picker.exe"
    exit 0
fi
exit 2
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'go.exe')
    $gitStub = Join-Path $stubDir 'git.exe'
    $goStub = Join-Path $stubDir 'go.exe'
    & chmod +x -- $gitStub $goStub

    $env:SHELL_PICKER_SOURCE_DIR = $sourceDir
    $env:COMMAND_LOG = $commandLog
    $env:GIT_HEAD = 'abc123'
    $env:GO_GOPATH = $goPath
    $env:PATH = $stubDir + [IO.Path]::PathSeparator + $oldPath

    $help = & $pwsh -NoProfile -NonInteractive -File $script '-Help' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $help -notlike '*Usage:*') { Fail '-Help failed' }

    $status = Invoke-Setup '-Unknown'
    if ($status -eq 0) { Fail 'unknown option unexpectedly succeeded' }

    $binary = Join-Path $goBin 'shell-picker.exe'
    @'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == version ]] && printf 'shell-picker dev\n'
'@ | Set-Content -LiteralPath $binary
    & chmod +x -- $binary
    $status = Invoke-Setup '-Check'
    if ($status -ne 0) { Fail 'matching shell-picker binary failed --check' }

    Set-Content -LiteralPath $binary -Value '#!/usr/bin/env bash'
    $status = Invoke-Setup '-Check'
    if ($status -eq 0) { Fail 'unexpected binary version passed --check' }

    Remove-Item -LiteralPath $binary
    $status = Invoke-Setup '-Apply'
    if ($status -ne 0 -or -not (Test-Path -LiteralPath $binary -PathType Leaf)) { Fail '--apply did not install the binary' }
    if ((Invoke-Setup '-Check') -ne 0) { Fail '-Check failed after -Apply' }

    Remove-Item -LiteralPath $sourceDir -Recurse -Force
    if ((Invoke-Setup '-Check') -eq 0) { Fail '-Check succeeded without the source repository' }

    Write-Output 'PASS: Windows shell-picker setup'
} finally {
    $env:PATH = $oldPath
    Remove-Item Env:SHELL_PICKER_SOURCE_DIR, Env:COMMAND_LOG, Env:GIT_HEAD, Env:GO_GOPATH -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
