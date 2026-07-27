$scriptPath = Join-Path $PSScriptRoot "..\codex-usage.ps1"
. $scriptPath -LibraryOnly

function New-TestWindow {
  param(
    [int]$UsedPercent,
    [AllowNull()][object]$ResetsAt,
    [AllowNull()][object]$WindowDurationMins
  )

  [pscustomobject]@{
    usedPercent = $UsedPercent
    resetsAt = $ResetsAt
    windowDurationMins = $WindowDurationMins
  }
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
