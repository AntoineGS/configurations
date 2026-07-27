[CmdletBinding()]
param(
  [switch]$LibraryOnly,
  [string]$CachePath = (Join-Path $env:LOCALAPPDATA "yasb\codex-usage.json"),
  [ValidateRange(1, 120)][int]$TimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-ApproximateDuration {
  param([long]$ActualMinutes, [long]$ExpectedMinutes)

  [math]::Abs($ActualMinutes - $ExpectedMinutes) -le ($ExpectedMinutes * 0.05)
}

function Format-ResetCountdown {
  param(
    [AllowNull()][object]$ResetAt,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )

  if ($null -eq $ResetAt) { return "--" }

  $remaining = [long]$ResetAt - $Now.ToUnixTimeSeconds()
  if ($remaining -le 0) { return "now" }

  $days = [math]::Floor($remaining / 86400)
  $hours = [math]::Floor(($remaining % 86400) / 3600)
  $minutes = [math]::Floor(($remaining % 3600) / 60)
  $parts = [System.Collections.Generic.List[string]]::new()
  if ($days -gt 0) { $parts.Add("${days}d") }
  if ($hours -gt 0) { $parts.Add("${hours}h") }
  if ($minutes -gt 0 -and $parts.Count -lt 2) { $parts.Add("${minutes}m") }
  if ($parts.Count -eq 0) { return "<1m" }

  ($parts | Select-Object -First 2) -join ""
}

function Get-WindowLabel {
  param(
    [AllowNull()][object]$DurationMinutes,
    [switch]$Secondary
  )

  if ($null -eq $DurationMinutes) {
    return $(if ($Secondary) { "Usage" } else { "Session" })
  }

  $duration = [long]$DurationMinutes
  if (Test-ApproximateDuration $duration 300) { return "Session" }
  if (Test-ApproximateDuration $duration 10080) { return "Weekly" }
  if (($duration % 1440) -eq 0) { return "Usage ($($duration / 1440)d)" }
  if (($duration % 60) -eq 0) { return "Usage ($($duration / 60)h)" }

  "Usage (${duration}m)"
}

function ConvertTo-CodexUsageOutput {
  param(
    [Parameter(Mandatory)][psobject]$RateLimits,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )

  if ($null -eq $RateLimits.primary) {
    throw "Codex did not return a primary usage window."
  }

  $primary = $RateLimits.primary
  $weekly = $RateLimits.secondary
  $mirrorPrimary = $false
  if ($null -eq $weekly) {
    if (
      $null -ne $primary.windowDurationMins -and
      (Test-ApproximateDuration ([long]$primary.windowDurationMins) 10080)
    ) {
      $weekly = $primary
      $mirrorPrimary = $true
    } else {
      throw "Codex did not return a weekly usage window."
    }
  }

  $primaryReset = Format-ResetCountdown -ResetAt $primary.resetsAt -Now $Now
  $weeklyReset = Format-ResetCountdown -ResetAt $weekly.resetsAt -Now $Now
  $lines = [System.Collections.Generic.List[string]]::new()
  if (-not $mirrorPrimary) {
    $primaryLabel = Get-WindowLabel -DurationMinutes $primary.windowDurationMins
    $lines.Add("${primaryLabel}: $($primary.usedPercent)% (resets in $primaryReset)")
  }
  $weeklyLabel = Get-WindowLabel -DurationMinutes $weekly.windowDurationMins -Secondary
  $lines.Add("${weeklyLabel}: $($weekly.usedPercent)% (resets in $weeklyReset)")

  [ordered]@{
    label = "$($weekly.usedPercent)%/$weeklyReset"
    weekly_percent = [int]$weekly.usedPercent
    weekly_reset = $weeklyReset
    primary_percent = [int]$primary.usedPercent
    primary_reset = $primaryReset
    tooltip = $lines -join "`n"
    stale = $false
  }
}
