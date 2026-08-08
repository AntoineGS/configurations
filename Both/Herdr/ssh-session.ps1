[CmdletBinding()]
param(
  [ValidateSet('Attach', 'Disable', 'Enable', 'Watch')]
  [string]$Mode = 'Attach',

  [int]$ParentProcessId = 0,

  [long]$ParentStartTimeUtcTicks = 0,

  [string]$HerdrPath,

  [string]$ReadyPath,

  [string]$TriggerPath,

  [string]$CancelPath
)

if ([string]::IsNullOrWhiteSpace($HerdrPath)) {
  $HerdrPath = (Get-Command herdr -ErrorAction Stop).Source
}

function Set-OpenCodeAnimations {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('Disable', 'Enable')]
    [string]$Action
  )

  try {
    $paneListJson = (& $HerdrPath pane list 2>$null) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($paneListJson)) {
      return $false
    }
    $paneList = $paneListJson | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    return $false
  }

  $allowedStates = @('idle', 'done', 'working')
  $script:OpenCodeAnimationCommandSent = $false
  $opencodePanes = @($paneList.result.panes | Where-Object { $_.agent -ieq 'opencode' })
  $panes = @($opencodePanes | Where-Object {
      $allowedStates -contains $_.agent_status
    })
  $changed = $false
  $complete = $true

  foreach ($pane in $panes) {
    & $HerdrPath pane send-keys $pane.pane_id 'ctrl+p' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      $complete = $false
      continue
    }

    Start-Sleep -Milliseconds 100
    & $HerdrPath pane send-text $pane.pane_id "$Action animations" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      $complete = $false
      continue
    }

    Start-Sleep -Milliseconds 100
    & $HerdrPath pane send-keys $pane.pane_id enter 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      $changed = $true
      $script:OpenCodeAnimationCommandSent = $true
    }
    else {
      $complete = $false
    }
  }

  return ($changed -and $complete)
}

function Restore-OpenCodeAnimations {
  param([switch]$UntilSuccess)

  for ($attempt = 0; $UntilSuccess -or $attempt -lt 20; $attempt++) {
    if (Set-OpenCodeAnimations -Action Enable) { return $true }
    Start-Sleep -Milliseconds 250
  }

  return $false
}

function Start-AnimationWatchdog {
  $parentProcess = Get-Process -Id $PID
  $powerShellPath = $parentProcess.Path
  $watchId = [Guid]::NewGuid().ToString('N')
  $readyPath = Join-Path ([IO.Path]::GetTempPath()) "herdr-opencode-$watchId.ready"
  $triggerPath = Join-Path ([IO.Path]::GetTempPath()) "herdr-opencode-$watchId.trigger"
  $cancelPath = Join-Path ([IO.Path]::GetTempPath()) "herdr-opencode-$watchId.cancel"
  $escapedScriptPath = $PSCommandPath.Replace("'", "''")
  $escapedHerdrPath = $HerdrPath.Replace("'", "''")
  $escapedReadyPath = $readyPath.Replace("'", "''")
  $escapedTriggerPath = $triggerPath.Replace("'", "''")
  $escapedCancelPath = $cancelPath.Replace("'", "''")
  $parentStartTicks = $parentProcess.StartTime.ToUniversalTime().Ticks
  $watchCommand = "& '$escapedScriptPath' -Mode Watch -ParentProcessId $PID -ParentStartTimeUtcTicks $parentStartTicks -HerdrPath '$escapedHerdrPath' -ReadyPath '$escapedReadyPath' -TriggerPath '$escapedTriggerPath' -CancelPath '$escapedCancelPath'"
  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watchCommand))
  $commandLine = '"{0}" -NoLogo -NoProfile -NonInteractive -EncodedCommand {1}' -f $powerShellPath, $encodedCommand

  try {
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{
      CreateFlags = [uint32]0x01000000 # CREATE_BREAKAWAY_FROM_JOB
    }
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
      CommandLine = $commandLine
      ProcessStartupInformation = $startup
    }
    if ($result.ReturnValue -ne 0) { return $null }

    for ($attempt = 0; $attempt -lt 40; $attempt++) {
      if (Test-Path -LiteralPath $readyPath) {
        return [pscustomobject]@{
          ReadyPath = $readyPath
          TriggerPath = $triggerPath
          CancelPath = $cancelPath
        }
      }
      if (!(Get-Process -Id $result.ProcessId -ErrorAction SilentlyContinue)) { break }
      Start-Sleep -Milliseconds 50
    }
    Set-Content -LiteralPath $cancelPath -Value cancel -NoNewline -ErrorAction SilentlyContinue
  }
  catch {
    return $null
  }

  return $null
}

if ($Mode -ne 'Attach') {
  if ($Mode -eq 'Watch') {
    if ($ParentProcessId -le 0 -or $ParentStartTimeUtcTicks -le 0 -or
      [string]::IsNullOrWhiteSpace($ReadyPath) -or [string]::IsNullOrWhiteSpace($TriggerPath) -or
      [string]::IsNullOrWhiteSpace($CancelPath)) {
      throw 'Watch mode requires parent identity and synchronization paths.'
    }

    try {
      Set-Content -LiteralPath $ReadyPath -Value ready -NoNewline
      while (!(Test-Path -LiteralPath $TriggerPath) -and !(Test-Path -LiteralPath $CancelPath)) {
        try {
          $parent = Get-Process -Id $ParentProcessId -ErrorAction Stop
          if ($parent.StartTime.ToUniversalTime().Ticks -ne $ParentStartTimeUtcTicks) { break }
        }
        catch {
          break
        }
        Start-Sleep -Milliseconds 250
      }
      if (Test-Path -LiteralPath $CancelPath) { return }
      $null = Restore-OpenCodeAnimations -UntilSuccess
    }
    finally {
      Remove-Item -LiteralPath $ReadyPath, $TriggerPath, $CancelPath -Force -ErrorAction SilentlyContinue
    }
    return
  }

  $null = Set-OpenCodeAnimations -Action $Mode
  return
}

$watchdog = $null
$animationsChanged = $false

try {
  $watchdog = Start-AnimationWatchdog
  if ($null -ne $watchdog) {
    $null = Set-OpenCodeAnimations -Action Disable
    $animationsChanged = $script:OpenCodeAnimationCommandSent
    if (!$animationsChanged) {
      Set-Content -LiteralPath $watchdog.CancelPath -Value cancel -NoNewline -ErrorAction SilentlyContinue
      $watchdog = $null
    }
  }
  & $HerdrPath
}
finally {
  if ($animationsChanged -and $null -ne $watchdog) {
    try {
      Set-Content -LiteralPath $watchdog.TriggerPath -Value restore -NoNewline -ErrorAction Stop
    }
    catch {
      $null = Restore-OpenCodeAnimations -UntilSuccess
    }
  }
}
