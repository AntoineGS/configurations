param(
    [switch]$Check,
    [switch]$Apply,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$prefix = if ([string]::IsNullOrWhiteSpace($env:OPENCODE_TOKENIZER_PREFIX)) {
    Join-Path $HOME '.config/opencode/plugins/vendor'
} else {
    $env:OPENCODE_TOKENIZER_PREFIX
}

function Test-Tokenizers {
    (Test-Path -LiteralPath (Join-Path $prefix 'node_modules/js-tiktoken/package.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $prefix 'node_modules/@huggingface/transformers/package.json') -PathType Leaf)
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
        if (Test-Tokenizers) { exit 0 }
        exit 1
}
if ($Apply) {
        & npm install 'js-tiktoken@latest' '@huggingface/transformers@^3.3.3' --omit=dev --no-audit --loglevel=error --prefix $prefix
        exit $LASTEXITCODE
}
if ($Help) {
        Write-Output "Usage: $([IO.Path]::GetFileName($PSCommandPath)) -Check|-Apply|-Help"
        exit 0
}
