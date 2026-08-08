Import-Module PSReadLine
Set-PSReadLineOption -EditMode Vi

$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'
$env:GIT_EDITOR = 'nvim'
$env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
$env:_ZO_FZF_OPTS = '--style=full --layout=reverse'

if (Get-Command carapace -ErrorAction SilentlyContinue) {
  Set-PSReadLineOption -Colors @{ Selection = "`e[7m" }
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  carapace _carapace | Out-String | Invoke-Expression
}

function Invoke-Starship-TransientFunction {
  &starship module character
}

function Get-ChildItemUnix {
  Get-ChildItem $Args[0] |
  Format-Table Mode, @{N = 'Owner'; E = { (Get-Acl $_.FullName).Owner } }, Length, LastWriteTime, @{N = 'Name'; E = { if ($_.Target) { $_.Name + ' -> ' + $_.Target } else { $_.Name } } }
}
Set-Alias -Name ll -Value Get-ChildItemUnix -Scope Global
function :q { exit }

if (Get-Command lazygit -ErrorAction SilentlyContinue) {
  Set-Alias -Name lg -Value lazygit -Scope Global
}

if (Get-Command opencode -ErrorAction SilentlyContinue) {
  Set-Alias -Name ocv -Value opencode -Scope Global
}

if (Get-Command claude -ErrorAction SilentlyContinue) {
  function clauded {
    & claude --dangerously-skip-permissions @args
  }
}

if (Get-Command yazi -ErrorAction SilentlyContinue) {
  function y {
    $temporaryFile = $null
    try {
      $temporaryFile = New-TemporaryFile
      & yazi @args "--cwd-file=$($temporaryFile.FullName)"

      $cwd = Get-Content -LiteralPath $temporaryFile.FullName -Raw -ErrorAction SilentlyContinue
      if ($null -eq $cwd) {
        return
      }
      $cwd = $cwd.Trim()
      if ([string]::IsNullOrEmpty($cwd)) {
        return
      }

      $location = Get-Location
      $target = Get-Item -LiteralPath $cwd -ErrorAction SilentlyContinue
      if ($location.Provider.Name -cne 'FileSystem' -or
          $null -eq $target -or
          -not $target.PSIsContainer -or
          $target.PSProvider.Name -cne 'FileSystem') {
        return
      }

      if ($target.FullName -cne $location.ProviderPath) {
        Set-Location -LiteralPath $target.FullName
      }
    }
    finally {
      if ($null -ne $temporaryFile) {
        Remove-Item -LiteralPath $temporaryFile.FullName -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

function attach_to_container {
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name
  )

  try {
    $docker = Get-Command docker -CommandType Application -ErrorAction Stop
    $output = @(& $docker.Source ps --format '{{json .}}' 2>&1)
    $exitCode = $LASTEXITCODE
  }
  catch {
    throw "docker ps failed: $($_.Exception.Message)"
  }

  try {
    [void][regex]::new($Name)
  }
  catch {
    throw "Invalid container image regex '$Name': $($_.Exception.Message)"
  }

  if ($null -ne $exitCode -and $exitCode -ne 0) {
    $detail = ($output | ForEach-Object { [string]$_ } | Where-Object { $_ } | Out-String).Trim()
    if ([string]::IsNullOrEmpty($detail)) {
      throw "docker ps failed with exit code $exitCode."
    }
    throw "docker ps failed: $detail"
  }

  $containers = foreach ($line in $output) {
    if ($line -isnot [string] -or [string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      ConvertFrom-Json -InputObject $line -ErrorAction Stop
    }
    catch {
      throw 'docker ps returned invalid JSON.'
    }
  }

  $container = $containers |
    Where-Object { $_.Image -and ([string]$_.Image -match $Name) } |
    Select-Object -First 1
  if ($null -eq $container) {
    throw "No running container matched '$Name' in Image."
  }

  Write-Host "Attaching to $($container.Names) ($($container.Image))"
  & $docker.Source exec -it $container.ID bash
}

function Update-HerdrWaypipeEnvironment {
  if ($env:HERDR_ENV -ne '1') {
    return
  }

  $now = [Environment]::TickCount64
  if ($null -ne $global:HerdrWaypipeEnvironmentLastRefresh -and
      $now - $global:HerdrWaypipeEnvironmentLastRefresh -lt 250) {
    return
  }

  $cachedHelper = $global:HerdrWaypipeEnvironmentHelper
  if ($null -eq $cachedHelper) {
    $helper = Get-Command herdr-waypipe-env -ErrorAction SilentlyContinue
    if ($null -eq $helper) {
      return
    }

    $helperPath = $helper.Source
    if ([string]::IsNullOrEmpty($helperPath)) {
      $helperPath = $helper.Name
    }
    $cachedHelper = [pscustomobject]@{
      Path = $helperPath
      IsNative = $helper.CommandType -in @('Application', 'ExternalScript')
    }
    $global:HerdrWaypipeEnvironmentHelper = $cachedHelper
  }

  $global:HerdrWaypipeEnvironmentLastRefresh = $now
  try {
    $lines = @(& $cachedHelper.Path read 2>$null)
    $helperSucceeded = $?
    $exitCode = $LASTEXITCODE
    if (-not $helperSucceeded -or
        ($cachedHelper.IsNative -and
          $null -ne $exitCode -and $exitCode -ne 0) -or
        $lines.Count -ne 3) {
      return
    }

    $values = @{}
    foreach ($line in $lines) {
      if ($line -notmatch '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DISPLAY)=(.*)$') {
        return
      }
      $key = $Matches[1]
      $value = $Matches[2]
      if ($values.ContainsKey($key) -or
          ($key -ne 'DISPLAY' -and [string]::IsNullOrEmpty($value))) {
        return
      }
      $values[$key] = $value
    }

    if ($values.Count -ne 3) {
      return
    }

    $env:WAYLAND_DISPLAY = $values['WAYLAND_DISPLAY']
    $env:XDG_RUNTIME_DIR = $values['XDG_RUNTIME_DIR']
    if ([string]::IsNullOrEmpty($values['DISPLAY'])) {
      Remove-Item Env:DISPLAY -ErrorAction SilentlyContinue
    }
    else {
      $env:DISPLAY = $values['DISPLAY']
    }
  }
  catch {
    $global:HerdrWaypipeEnvironmentHelper = $null
    return
  }
}

function Invoke-Starship-PreCommand {
  Update-HerdrWaypipeEnvironment
}

Import-Module "$HOME/.config/shell-picker/shell-picker.psd1" -ErrorAction Stop
Register-ShellPicker -PickerPath (Get-Command shell-picker.exe -CommandType Application -ErrorAction Stop).Source

Invoke-Expression (&starship init powershell --print-full-init | Out-String)
Set-PSReadLineOption -ViModeIndicator Cursor
Enable-TransientPrompt

$fzfApplication = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue
if ($null -ne $fzfApplication) {
  $script:fzfPath = $fzfApplication.Source
  $script:fzfHistoryHandler = {
    try {
      $buffer = ''
      $cursor = 0
      [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
      $escapedBuffer = $buffer.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')

      $candidates = @(
        foreach ($historyItem in [Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()) {
          $command = [string]$historyItem.CommandLine
          if ([string]::IsNullOrWhiteSpace($command) -or
              $command.IndexOf([char]0) -ge 0) {
            continue
          }

          $display = $command.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
          $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($command))
          "$display`t$payload"
        }
      )
      if ($candidates.Count -eq 0) {
        return
      }

      $fzfArguments = @(
        '--no-multi'
        '--no-sort'
        '--tac'
        '--delimiter'
        "`t"
        '--nth'
        '1'
        '--with-nth'
        '1'
        '--bind'
        'ctrl-c:abort'
        '--query'
        $escapedBuffer
      )
      $selection = @($candidates | & $script:fzfPath @fzfArguments 2>$null)
      $exitCode = $LASTEXITCODE
      if ($exitCode -ne 0 -or $selection.Count -ne 1) {
        return
      }

      $selected = [string]$selection[0]
      $delimiter = [char]9
      $delimiterIndex = $selected.IndexOf($delimiter)
      if ($delimiterIndex -lt 1 -or
          $delimiterIndex -ne $selected.LastIndexOf($delimiter)) {
        return
      }

      $display = $selected.Substring(0, $delimiterIndex)
      $payload = $selected.Substring($delimiterIndex + 1)
      if ([string]::IsNullOrEmpty($payload)) {
        return
      }

      $bytes = [Convert]::FromBase64String($payload)
      if ([Convert]::ToBase64String($bytes) -cne $payload) {
        return
      }
      $command = [System.Text.Encoding]::UTF8.GetString($bytes)
      if ([string]::IsNullOrWhiteSpace($command) -or
          $command.IndexOf([char]0) -ge 0) {
        return
      }

      $expectedDisplay = $command.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
      if ($display -cne $expectedDisplay) {
        return
      }

      [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $buffer.Length, $command)
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($command.Length)
    }
    catch {
    }
  }
  Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock $script:fzfHistoryHandler -BriefDescription fzf-history -ViMode Insert
}

$zoxide = Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue
if ($null -ne $zoxide) {
  try {
    $zoxideInit = & $zoxide.Source init powershell | Out-String
    $zoxideExitCode = $LASTEXITCODE
    if ($zoxideExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($zoxideInit)) {
      $global:__zoxide_hooked = 0
      Invoke-Expression -Command $zoxideInit -ErrorAction Stop

      $zCommand = Get-Command z -ErrorAction SilentlyContinue
      $ziCommand = Get-Command zi -ErrorAction SilentlyContinue
      if ($null -ne $zCommand -and $null -ne $ziCommand) {
        Set-Alias -Name cd -Value z -Option AllScope -Scope Global -Force
        Set-Alias -Name cdi -Value zi -Option AllScope -Scope Global -Force
      }
    }
  }
  catch {
  }
}

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

$pwshArguments = [Environment]::GetCommandLineArgs()
$pwshNonInteractive = $pwshArguments -contains '-NonInteractive' -or
  $pwshArguments -contains '-noni'
$pwshScriptMode = $pwshArguments | Where-Object {
  $_ -in @(
    '-Command', '-c', '-CommandWithArgs', '-cwa',
    '-EncodedCommand', '-e', '-ec', '-enc', '-File', '-f'
  )
}

if (-not [string]::IsNullOrEmpty($env:SSH_TTY) -and
    $env:HERDR_ENV -ne '1' -and
    -not $pwshNonInteractive -and
    -not $pwshScriptMode) {
  $herdr = Get-Command herdr -ErrorAction SilentlyContinue
  if ($null -ne $herdr) {
    $waypipeHelper = Get-Command herdr-waypipe-env -ErrorAction SilentlyContinue
    if ($null -ne $waypipeHelper) {
      try {
        & $waypipeHelper.Name publish *> $null
      }
      catch {
      }
    }
    $sshWrapper = Join-Path $env:APPDATA 'herdr\ssh-session.ps1'
    if (Test-Path -LiteralPath $sshWrapper) {
      & $sshWrapper Attach
    }
    else {
      & $herdr.Name
    }
  }
}
