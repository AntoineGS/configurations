Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '../setup-context-tokenizers.ps1'
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('context-tokenizers-' + [guid]::NewGuid().ToString('N'))
$stubDir = Join-Path $tmpDir 'bin'
$prefix = Join-Path $tmpDir 'vendor'
$npmLog = Join-Path $tmpDir 'npm.log'
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
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    Set-Content -LiteralPath $npmLog -Value '' -NoNewline
    @'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$NPM_LOG"
if [[ "${NPM_FAIL_STATUS:-0}" -ne 0 ]]; then exit "$NPM_FAIL_STATUS"; fi
mkdir -p -- "$NPM_PREFIX/node_modules/js-tiktoken" "$NPM_PREFIX/node_modules/@huggingface/transformers"
: > "$NPM_PREFIX/node_modules/js-tiktoken/package.json"
: > "$NPM_PREFIX/node_modules/@huggingface/transformers/package.json"
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'npm')
    $npmStub = Join-Path $stubDir 'npm'
    & chmod +x -- $npmStub

    $env:OPENCODE_TOKENIZER_PREFIX = $prefix
    $env:NPM_LOG = $npmLog
    $env:NPM_PREFIX = $prefix
    $env:NPM_FAIL_STATUS = '0'
    $env:PATH = $stubDir + [IO.Path]::PathSeparator + $oldPath

    $help = & $pwsh -NoProfile -NonInteractive -File $script '-Help' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $help -notlike '*Usage:*') { Fail '-Help failed' }

    $status = Invoke-Setup '-Unknown'
    if ($status -eq 0) { Fail 'unknown option unexpectedly succeeded' }

    $status = Invoke-Setup '-Check'
    if ($status -eq 0) { Fail '--check succeeded without tokenizer packages' }
    if ((Get-Item -LiteralPath $npmLog).Length -ne 0) { Fail '--check invoked npm' }

    $status = Invoke-Setup '-Apply'
    if ($status -ne 0) { Fail '--apply failed with a working npm' }
    $expected = "install js-tiktoken@latest @huggingface/transformers@^3.3.3 --omit=dev --no-audit --loglevel=error --prefix $prefix"
    if ((Get-Content -LiteralPath $npmLog -Raw).Trim() -ne $expected) { Fail 'npm arguments differ' }
    if ((Invoke-Setup '-Check') -ne 0) { Fail '-Check failed after -Apply' }

    Remove-Item -LiteralPath (Join-Path $prefix 'node_modules/js-tiktoken/package.json'), (Join-Path $prefix 'node_modules/@huggingface/transformers/package.json')
    $env:NPM_FAIL_STATUS = '19'
    $status = Invoke-Setup '-Apply'
    if ($status -ne 19) { Fail "npm failure exited with $status instead of 19" }

    Write-Output 'PASS: Windows context tokenizer setup'
} finally {
    $env:PATH = $oldPath
    Remove-Item Env:OPENCODE_TOKENIZER_PREFIX, Env:NPM_LOG, Env:NPM_PREFIX, Env:NPM_FAIL_STATUS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
