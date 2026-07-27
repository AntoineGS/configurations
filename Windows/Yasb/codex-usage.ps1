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

function ConvertTo-UsagePercent {
  param(
    [AllowNull()][object]$Value,
    [string]$WindowName
  )

  $numericTypes = @(
    [byte], [sbyte], [short], [ushort], [int], [uint], [long], [ulong], [float], [double], [decimal]
  )
  $isNumeric = $null -ne $Value -and $Value.GetType() -in $numericTypes
  if (-not $isNumeric -or $Value -lt 0 -or $Value -gt 100 -or ($Value % 1) -ne 0) {
    throw "Codex $WindowName usedPercent must be a numeric integer from 0 to 100."
  }

  [int]$Value
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

  $primaryPercent = ConvertTo-UsagePercent -Value $primary.usedPercent -WindowName "primary"
  if ($mirrorPrimary) {
    $weeklyPercent = $primaryPercent
  } else {
    $weeklyPercent = ConvertTo-UsagePercent -Value $weekly.usedPercent -WindowName "weekly"
  }

  $primaryReset = Format-ResetCountdown -ResetAt $primary.resetsAt -Now $Now
  $weeklyReset = Format-ResetCountdown -ResetAt $weekly.resetsAt -Now $Now
  $lines = [System.Collections.Generic.List[string]]::new()
  if (-not $mirrorPrimary) {
    $primaryLabel = Get-WindowLabel -DurationMinutes $primary.windowDurationMins
    $lines.Add("${primaryLabel}: ${primaryPercent}% (resets in $primaryReset)")
  }
  $weeklyLabel = Get-WindowLabel -DurationMinutes $weekly.windowDurationMins -Secondary
  $lines.Add("${weeklyLabel}: ${weeklyPercent}% (resets in $weeklyReset)")

  [ordered]@{
    label = "${weeklyPercent}%/$weeklyReset"
    weekly_percent = $weeklyPercent
    weekly_reset = $weeklyReset
    primary_percent = $primaryPercent
    primary_reset = $primaryReset
    tooltip = $lines -join "`n"
    stale = $false
  }
}

function Format-CacheAge {
  param(
    [DateTimeOffset]$CacheTime,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )

  $age = $Now - $CacheTime
  if ($age.TotalMinutes -lt 1) { return "just now" }
  if ($age.TotalHours -lt 1) { return "$([math]::Floor($age.TotalMinutes))m old" }
  if ($age.TotalDays -lt 1) { return "$([math]::Floor($age.TotalHours))h old" }

  "$([math]::Floor($age.TotalDays))d old"
}

function Get-CodexUsageProperty {
  param(
    [AllowNull()][object]$InputObject,
    [string]$Name
  )

  if ($null -eq $InputObject) {
    throw "Codex usage cache is empty."
  }
  if ($InputObject -is [System.Collections.IDictionary]) {
    if (-not $InputObject.Contains($Name)) {
      throw "Codex usage cache is missing $Name."
    }
    return $InputObject[$Name]
  }

  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) {
    throw "Codex usage cache is missing $Name."
  }

  $property.Value
}

function Write-CodexUsageCache {
  param(
    [Parameter(Mandatory)][object]$Output,
    [Parameter(Mandatory)][string]$CachePath
  )

  if ((Get-CodexUsageProperty -InputObject $Output -Name "stale") -eq $true) {
    return
  }

  $fieldNames = @(
    "label", "weekly_percent", "weekly_reset", "primary_percent", "primary_reset", "tooltip", "stale"
  )
  $normalized = [ordered]@{}
  foreach ($fieldName in $fieldNames) {
    $normalized[$fieldName] = Get-CodexUsageProperty -InputObject $Output -Name $fieldName
  }

  $fullCachePath = [System.IO.Path]::GetFullPath($CachePath)
  $parentPath = [System.IO.Path]::GetDirectoryName($fullCachePath)
  [System.IO.Directory]::CreateDirectory($parentPath) | Out-Null
  $temporaryPath = Join-Path $parentPath ".$([System.IO.Path]::GetFileName($fullCachePath)).$([guid]::NewGuid()).tmp"

  try {
    $json = $normalized | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $fullCachePath, $true)
  } finally {
    if ([System.IO.File]::Exists($temporaryPath)) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Get-CodexUsageFallback {
  param(
    [AllowNull()][object]$ErrorMessage,
    [Parameter(Mandatory)][string]$CachePath,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )

  $reason = ([string]$ErrorMessage) -replace "\r\n|\r|\n", " "
  if ($reason.Length -gt 160) {
    $reason = $reason.Substring(0, 160)
  }

  try {
    $cacheFile = Get-Item -LiteralPath $CachePath -ErrorAction Stop
    $cache = Get-Content -Raw -LiteralPath $CachePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $fieldNames = @(
      "label", "weekly_percent", "weekly_reset", "primary_percent", "primary_reset", "tooltip", "stale"
    )
    $normalized = [ordered]@{}
    foreach ($fieldName in $fieldNames) {
      $normalized[$fieldName] = Get-CodexUsageProperty -InputObject $cache -Name $fieldName
    }

    $age = Format-CacheAge -CacheTime ([DateTimeOffset]$cacheFile.LastWriteTimeUtc) -Now $Now
    $normalized.tooltip = "Stale (${age}): $reason`n$($normalized.tooltip)"
    $normalized.stale = $true
    return $normalized
  } catch {
    return [ordered]@{
      label = "Codex ?"
      weekly_percent = $null
      weekly_reset = "--"
      primary_percent = $null
      primary_reset = "--"
      tooltip = "Codex usage unavailable: $reason"
      stale = $true
    }
  }
}
