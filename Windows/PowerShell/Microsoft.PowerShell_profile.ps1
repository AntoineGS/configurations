Import-Module PSReadLine
Set-PSReadLineOption -EditMode Vi

$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'
$env:GIT_EDITOR = 'nvim'

function Invoke-Starship-TransientFunction {
  &starship module character
}

function Get-ChildItemUnix {
  Get-ChildItem $Args[0] |
  Format-Table Mode, @{N = 'Owner'; E = { (Get-Acl $_.FullName).Owner } }, Length, LastWriteTime, @{N = 'Name'; E = { if ($_.Target) { $_.Name + ' -> ' + $_.Target } else { $_.Name } } }
}
New-Alias ll Get-ChildItemUnix

Invoke-Expression (&starship init powershell --print-full-init | Out-String)
Enable-TransientPrompt

function refreshenv {
  if ([string]::IsNullOrEmpty($env:ChocolateyInstall)) {
    throw "ChocolateyInstall is not set; cannot load the Chocolatey PowerShell profile."
  }

  $chocolateyProfile = Join-Path $env:ChocolateyInstall "helpers\chocolateyProfile.psm1"
  if (!(Test-Path -LiteralPath $chocolateyProfile)) {
    throw "Chocolatey PowerShell profile not found at '$chocolateyProfile'."
  }

  Import-Module $chocolateyProfile -Global
  Update-SessionEnvironment
}

if (![string]::IsNullOrEmpty($env:SSH_CONNECTION) -and $env:HERDR_ENV -ne '1') {
  $sshWrapper = Join-Path $env:APPDATA 'herdr\ssh-session.ps1'
  if (Test-Path -LiteralPath $sshWrapper) {
    & $sshWrapper Attach
  }
  else {
    & herdr
  }
}
