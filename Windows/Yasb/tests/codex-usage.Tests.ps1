$scriptPath = Join-Path $PSScriptRoot "..\codex-usage.ps1"
. $scriptPath -LibraryOnly

function New-TestWindow {
  param(
    [AllowNull()][object]$UsedPercent,
    [AllowNull()][object]$ResetsAt,
    [AllowNull()][object]$WindowDurationMins
  )

  [pscustomobject]@{
    usedPercent = $UsedPercent
    resetsAt = $ResetsAt
    windowDurationMins = $WindowDurationMins
  }
}

function New-TestOutput {
  param([bool]$Stale = $false)

  [ordered]@{
    label = "34%/6d20h"
    weekly_percent = 34
    weekly_reset = "6d20h"
    primary_percent = 12
    primary_reset = "2h30m"
    tooltip = "Session: 12% (resets in 2h30m)`nWeekly: 34% (resets in 6d20h)"
    stale = $Stale
  }
}

function Assert-InvalidUsagePercent {
  param(
    [AllowNull()][object]$UsedPercent,
    [DateTimeOffset]$Now
  )

  $primaryLimits = [pscustomobject]@{
    primary = New-TestWindow $UsedPercent $null 300
    secondary = New-TestWindow 20 $null 10080
  }
  $weeklyLimits = [pscustomobject]@{
    primary = New-TestWindow 10 $null 300
    secondary = New-TestWindow $UsedPercent $null 10080
  }

  { ConvertTo-CodexUsageOutput -RateLimits $primaryLimits -Now $Now } |
    Should Throw "primary usedPercent must be a numeric integer from 0 to 100"
  { ConvertTo-CodexUsageOutput -RateLimits $weeklyLimits -Now $Now } |
    Should Throw "weekly usedPercent must be a numeric integer from 0 to 100"
}

Describe "Script entry contract" {
  $scriptAst = (Get-Command $scriptPath).ScriptBlock.Ast

  It "loads as a library without emitting output" {
    @(& $scriptPath -LibraryOnly).Count | Should Be 0
  }

  It "uses the required cache path and timeout defaults" {
    $cachePathParameter = $scriptAst.ParamBlock.Parameters |
      Where-Object { $_.Name.VariablePath.UserPath -eq "CachePath" }
    $timeoutParameter = $scriptAst.ParamBlock.Parameters |
      Where-Object { $_.Name.VariablePath.UserPath -eq "TimeoutSeconds" }

    $cachePathParameter.DefaultValue.Extent.Text |
      Should Be '(Join-Path $env:LOCALAPPDATA "yasb\codex-usage.json")'
    $timeoutParameter.DefaultValue.Extent.Text | Should Be "15"
  }

  It "validates the timeout range" {
    { & $scriptPath -LibraryOnly -TimeoutSeconds 0 } | Should Throw "TimeoutSeconds"
    { & $scriptPath -LibraryOnly -TimeoutSeconds 121 } | Should Throw "TimeoutSeconds"
  }

  It "enables strict mode latest" {
    {
      Set-StrictMode -Off
      . $scriptPath -LibraryOnly
      $values = @(1)
      $values[1]
    } | Should Throw "outside the bounds"
  }

  It "declares strict mode latest literally" {
    $scriptAst.Extent.Text | Should Match "(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$"
  }

  It "stops on non-terminating errors" {
    {
      $ErrorActionPreference = "Continue"
      . $scriptPath -LibraryOnly
      Write-Error "script contract probe"
    } | Should Throw "script contract probe"
  }
}

Describe "Test-ApproximateDuration" {
  It "accepts durations within five percent" {
    Test-ApproximateDuration -ActualMinutes 285 -ExpectedMinutes 300 | Should Be $true
    Test-ApproximateDuration -ActualMinutes 315 -ExpectedMinutes 300 | Should Be $true
  }

  It "rejects durations beyond five percent" {
    Test-ApproximateDuration -ActualMinutes 284 -ExpectedMinutes 300 | Should Be $false
    Test-ApproximateDuration -ActualMinutes 316 -ExpectedMinutes 300 | Should Be $false
  }
}

Describe "Format-ResetCountdown" {
  $now = [DateTimeOffset]::Parse("2026-07-27T12:00:00Z")

  It "formats day and hour units without spaces" {
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + (6 * 86400) + (20 * 3600)) -Now $now |
      Should Be "6d20h"
  }

  It "formats hour and minute units" {
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + (2 * 3600) + (30 * 60)) -Now $now |
      Should Be "2h30m"
  }

  It "uses at most the two largest nonzero units" {
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + 86400 + (2 * 3600) + (3 * 60)) -Now $now |
      Should Be "1d2h"
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + 86400 + (5 * 60)) -Now $now |
      Should Be "1d5m"
  }

  It "formats resets under one minute" {
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + 59) -Now $now | Should Be "<1m"
  }

  It "handles null and elapsed resets" {
    Format-ResetCountdown -ResetAt $null -Now $now | Should Be "--"
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() - 1) -Now $now | Should Be "now"
  }
}

Describe "Get-WindowLabel" {
  It "recognizes approximate session and weekly durations" {
    Get-WindowLabel -DurationMinutes 315 | Should Be "Session"
    Get-WindowLabel -DurationMinutes 9576 -Secondary | Should Be "Weekly"
  }

  It "describes nonstandard exactly divisible durations" {
    Get-WindowLabel -DurationMinutes 2880 -Secondary | Should Be "Usage (2d)"
    Get-WindowLabel -DurationMinutes 120 -Secondary | Should Be "Usage (2h)"
    Get-WindowLabel -DurationMinutes 90 -Secondary | Should Be "Usage (90m)"
  }

  It "uses primary and secondary fallbacks for null durations" {
    Get-WindowLabel -DurationMinutes $null | Should Be "Session"
    Get-WindowLabel -DurationMinutes $null -Secondary | Should Be "Usage"
  }
}

Describe "ConvertTo-CodexUsageOutput" {
  $now = [DateTimeOffset]::Parse("2026-07-27T12:00:00Z")

  It "uses a seven-day secondary window for the weekly output" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 12 ($now.ToUnixTimeSeconds() + 9000) 300
      secondary = New-TestWindow 34 ($now.ToUnixTimeSeconds() + 590400) 10080
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now

    ($result.Keys -join ",") | Should Be "label,weekly_percent,weekly_reset,primary_percent,primary_reset,tooltip,stale"
    $result.label | Should Be "34%/6d20h"
    $result.weekly_percent | Should Be 34
    $result.weekly_reset | Should Be "6d20h"
    $result.primary_percent | Should Be 12
    $result.primary_reset | Should Be "2h30m"
    $result.tooltip | Should Be "Session: 12% (resets in 2h30m)`nWeekly: 34% (resets in 6d20h)"
    $result.stale | Should Be $false
  }

  It "mirrors a lone seven-day primary window without duplicating the tooltip" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 6 ($now.ToUnixTimeSeconds() + 518400) 10080
      secondary = $null
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now

    $result.label | Should Be "6%/6d"
    $result.weekly_percent | Should Be 6
    $result.primary_percent | Should Be 6
    $result.tooltip | Should Be "Weekly: 6% (resets in 6d)"
  }

  It "preserves null reset formatting in normalized output" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 12 $null 300
      secondary = New-TestWindow 34 $null 10080
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now

    $result.label | Should Be "34%/--"
    $result.primary_reset | Should Be "--"
    $result.weekly_reset | Should Be "--"
  }

  It "clamps elapsed resets in normalized output" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 12 ($now.ToUnixTimeSeconds() - 2) 300
      secondary = New-TestWindow 34 ($now.ToUnixTimeSeconds() - 1) 10080
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now

    $result.label | Should Be "34%/now"
    $result.primary_reset | Should Be "now"
    $result.weekly_reset | Should Be "now"
  }

  It "labels a nonstandard secondary duration explicitly" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 10 ($now.ToUnixTimeSeconds() + 3600) 300
      secondary = New-TestWindow 44 ($now.ToUnixTimeSeconds() + 90000) 2880
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now

    $result.tooltip | Should Be "Session: 10% (resets in 1h)`nUsage (2d): 44% (resets in 1d1h)"
  }

  It "rejects null usage percentages" {
    Assert-InvalidUsagePercent -UsedPercent $null -Now $now
  }

  It "rejects fractional usage percentages" {
    Assert-InvalidUsagePercent -UsedPercent 12.5 -Now $now
  }

  It "rejects nonnumeric usage percentages" {
    Assert-InvalidUsagePercent -UsedPercent "12" -Now $now
  }

  It "rejects usage percentages below zero" {
    Assert-InvalidUsagePercent -UsedPercent (-1) -Now $now
  }

  It "rejects usage percentages above 100" {
    Assert-InvalidUsagePercent -UsedPercent 101 -Now $now
  }

  It "requires a primary window" {
    $limits = [pscustomobject]@{
      primary = $null
      secondary = New-TestWindow 34 ($now.ToUnixTimeSeconds() + 590400) 10080
    }

    { ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now } | Should Throw "primary usage window"
  }

  It "rejects a response with no weekly window" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 10 ($now.ToUnixTimeSeconds() + 3600) 300
      secondary = $null
    }

    { ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now } | Should Throw "weekly usage window"
  }
}

Describe "Format-CacheAge" {
  $now = [DateTimeOffset]::Parse("2026-07-27T12:00:00Z")

  It "formats cache age boundaries using whole units" {
    Format-CacheAge -CacheTime $now.AddSeconds(-59) -Now $now | Should Be "just now"
    Format-CacheAge -CacheTime $now.AddMinutes(-1) -Now $now | Should Be "1m old"
    Format-CacheAge -CacheTime $now.AddSeconds(-3599) -Now $now | Should Be "59m old"
    Format-CacheAge -CacheTime $now.AddHours(-1) -Now $now | Should Be "1h old"
    Format-CacheAge -CacheTime $now.AddSeconds(-86399) -Now $now | Should Be "23h old"
    Format-CacheAge -CacheTime $now.AddDays(-1) -Now $now | Should Be "1d old"
  }

  It "treats a future cache timestamp as just now" {
    Format-CacheAge -CacheTime $now.AddMinutes(5) -Now $now | Should Be "just now"
  }
}

Describe "Write-CodexUsageCache" {
  It "atomically replaces the cache with normalized output" {
    $cachePath = Join-Path $TestDrive "replace\codex-usage.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $cachePath) | Out-Null
    "old cache" | Set-Content -LiteralPath $cachePath

    Write-CodexUsageCache -Output (New-TestOutput) -CachePath $cachePath

    $cached = Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json
    $cached.label | Should Be "34%/6d20h"
    $cached.weekly_percent | Should Be 34
    $cached.stale | Should Be $false
  }

  It "creates the cache parent directory" {
    $cachePath = Join-Path $TestDrive "new\nested\codex-usage.json"

    Write-CodexUsageCache -Output (New-TestOutput) -CachePath $cachePath

    Test-Path -LiteralPath $cachePath | Should Be $true
  }

  It "writes exactly the seven allowed normalized fields" {
    $cachePath = Join-Path $TestDrive "allowed\codex-usage.json"
    $output = New-TestOutput
    $output.credentials = "secret"
    $output.app_server_message = "upstream message"
    $output.upstream_response = @{ access_token = "token" }

    Write-CodexUsageCache -Output $output -CachePath $cachePath

    $cached = Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json
    ($cached.PSObject.Properties.Name -join ",") |
      Should Be "label,weekly_percent,weekly_reset,primary_percent,primary_reset,tooltip,stale"
  }

  It "does not leave a same-directory temporary file" {
    $cachePath = Join-Path $TestDrive "cleanup\codex-usage.json"

    Write-CodexUsageCache -Output (New-TestOutput) -CachePath $cachePath

    @(Get-ChildItem -LiteralPath (Split-Path -Parent $cachePath) -File).Count | Should Be 1
  }

  It "does not overwrite the cache with stale fallback modifications" {
    $cachePath = Join-Path $TestDrive "fresh-only\codex-usage.json"
    Write-CodexUsageCache -Output (New-TestOutput) -CachePath $cachePath
    $original = Get-Content -Raw -LiteralPath $cachePath
    $fallback = New-TestOutput -Stale $true
    $fallback.tooltip = "Stale (1h old): failed`n$($fallback.tooltip)"

    Write-CodexUsageCache -Output $fallback -CachePath $cachePath

    Get-Content -Raw -LiteralPath $cachePath | Should Be $original
  }
}

Describe "Get-CodexUsageFallback" {
  $now = [DateTimeOffset]::Parse("2026-07-27T12:00:00Z")

  It "returns cached normalized data marked stale with its age and reason" {
    $cachePath = Join-Path $TestDrive "valid\codex-usage.json"
    Write-CodexUsageCache -Output (New-TestOutput) -CachePath $cachePath
    [System.IO.File]::SetLastWriteTimeUtc($cachePath, $now.AddHours(-1).UtcDateTime)

    $result = Get-CodexUsageFallback -ErrorMessage "request failed" -CachePath $cachePath -Now $now

    ($result.Keys -join ",") | Should Be "label,weekly_percent,weekly_reset,primary_percent,primary_reset,tooltip,stale"
    $result.label | Should Be "34%/6d20h"
    $result.weekly_percent | Should Be 34
    $result.weekly_reset | Should Be "6d20h"
    $result.primary_percent | Should Be 12
    $result.primary_reset | Should Be "2h30m"
    $result.tooltip | Should Be "Stale (1h old): request failed`nSession: 12% (resets in 2h30m)`nWeekly: 34% (resets in 6d20h)"
    $result.stale | Should Be $true
  }

  It "returns unavailable output when no cache exists" {
    $result = Get-CodexUsageFallback -ErrorMessage "not signed in" -CachePath (Join-Path $TestDrive "missing.json") -Now $now

    ($result.Keys -join ",") | Should Be "label,weekly_percent,weekly_reset,primary_percent,primary_reset,tooltip,stale"
    $result.label | Should Be "Codex ?"
    $result.weekly_percent | Should Be $null
    $result.weekly_reset | Should Be "--"
    $result.primary_percent | Should Be $null
    $result.primary_reset | Should Be "--"
    $result.tooltip | Should Be "Codex usage unavailable: not signed in"
    $result.stale | Should Be $true
  }

  It "returns unavailable output for malformed cache JSON" {
    $cachePath = Join-Path $TestDrive "malformed.json"
    "{not json" | Set-Content -LiteralPath $cachePath

    $result = Get-CodexUsageFallback -ErrorMessage "offline" -CachePath $cachePath -Now $now

    $result.label | Should Be "Codex ?"
    $result.tooltip | Should Be "Codex usage unavailable: offline"
  }

  It "returns unavailable output when a normalized field is missing" {
    $cachePath = Join-Path $TestDrive "missing-field.json"
    $incomplete = New-TestOutput
    $incomplete.Remove("primary_reset")
    $incomplete | ConvertTo-Json | Set-Content -LiteralPath $cachePath

    $result = Get-CodexUsageFallback -ErrorMessage "offline" -CachePath $cachePath -Now $now

    $result.label | Should Be "Codex ?"
    $result.primary_reset | Should Be "--"
    $result.tooltip | Should Be "Codex usage unavailable: offline"
  }

  It "returns unavailable output when all cache fields exist but usage data is empty" {
    $cachePath = Join-Path $TestDrive "empty-fields.json"
    $empty = [ordered]@{
      label = "   "
      weekly_percent = $null
      weekly_reset = "--"
      primary_percent = $null
      primary_reset = "--"
      tooltip = ""
      stale = $false
    }
    $empty | ConvertTo-Json | Set-Content -LiteralPath $cachePath

    $result = Get-CodexUsageFallback -ErrorMessage "offline" -CachePath $cachePath -Now $now

    ($result.Keys -join ",") | Should Be "label,weekly_percent,weekly_reset,primary_percent,primary_reset,tooltip,stale"
    $result.label | Should Be "Codex ?"
    $result.weekly_percent | Should Be $null
    $result.weekly_reset | Should Be "--"
    $result.primary_percent | Should Be $null
    $result.primary_reset | Should Be "--"
    $result.tooltip | Should Be "Codex usage unavailable: offline"
    $result.stale | Should Be $true
  }

  It "replaces reason newlines and limits the displayed reason to 160 characters" {
    $reason = ("x" * 80) + "`r`n" + ("y" * 100)
    $expectedReason = (($reason -replace "`r`n|`r|`n", " ").Substring(0, 160))

    $result = Get-CodexUsageFallback -ErrorMessage $reason -CachePath (Join-Path $TestDrive "sanitized.json") -Now $now

    $result.tooltip | Should Be "Codex usage unavailable: $expectedReason"
    $result.tooltip | Should Not Match "`r|`n"
  }
}
