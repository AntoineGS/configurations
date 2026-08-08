$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$yamlPath = Join-Path $repoRoot 'tidydots.yaml'
$linuxScript = Join-Path $repoRoot 'Both\ShellPicker\manage-binary.sh'
$windowsScript = Join-Path $repoRoot 'Both\ShellPicker\Manage-ShellPickerBinary.ps1'
$yaml = Get-Content -LiteralPath $yamlPath -Raw

Describe 'Shell-picker tidydots script extraction' {
  It 'keeps binary management in dedicated scripts' {
    Test-Path -LiteralPath $linuxScript -PathType Leaf | Should Be $true
    Test-Path -LiteralPath $windowsScript -PathType Leaf | Should Be $true
    $yaml | Should Match ([regex]::Escape('bash "$HOME/.config/shell-picker/manage-binary.sh" check'))
    $yaml | Should Match ([regex]::Escape('bash "$HOME/.config/shell-picker/manage-binary.sh" install'))
    $yaml | Should Match ([regex]::Escape('Manage-ShellPickerBinary.ps1" -Check'))
    $yaml | Should Match ([regex]::Escape('Manage-ShellPickerBinary.ps1"'))
    $yaml | Should Not Match 'powershell\.exe.+-Command "& \{'
  }

  It 'parses the Windows helper' {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
      $windowsScript,
      [ref]$tokens,
      [ref]$errors
    ) | Out-Null
    @($errors).Count | Should Be 0
  }

  It 'parses the Linux helper' {
    $bash = Get-Command bash -ErrorAction Stop
    & $bash.Source -n './Both/ShellPicker/manage-binary.sh'
    $LASTEXITCODE | Should Be 0
  }
}
