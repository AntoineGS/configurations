# YASB Codex Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a YASB custom widget that displays Codex weekly usage and reset time using Codex app-server, with a safe cached fallback.

**Architecture:** A PowerShell adapter owns the Codex JSONL exchange, converts rate-limit windows into one stable JSON object, and caches only that normalized object. YASB polls the adapter every five minutes and renders its preformatted label and tooltip; tidydots deploys the adapter beside the existing YASB configuration.

**Tech Stack:** PowerShell 7.6, Pester 3.4, Codex CLI 0.145 app-server JSON-RPC, YASB 2.0.5 CustomWidget, YAML/CSS, tidydots v3

---

## File Structure

- Create `Windows/Yasb/codex-usage.ps1`: pure formatting/normalization functions, cache handling, app-server process exchange, and the one-object stdout entry point.
- Create `Windows/Yasb/tests/codex-usage.Tests.ps1`: Pester coverage for window selection, countdowns, and cache fallback.
- Modify `Windows/Yasb/config.yaml:35-68`: activate and define the custom widget.
- Modify `Windows/Yasb/styles.css:37-50`: add the dim Codex widget treatment.
- Modify `tidydots.yaml:282-289`: deploy the helper with the other YASB files.

The helper stays in one file because it is deployed as one user-facing command. Tests load it with `-LibraryOnly`, keeping all data transformation testable without starting Codex.

### Task 1: Rate-Limit Normalization

**Files:**
- Create: `Windows/Yasb/codex-usage.ps1`
- Create: `Windows/Yasb/tests/codex-usage.Tests.ps1`

- [ ] **Step 1: Write failing normalization and countdown tests**

Create `Windows/Yasb/tests/codex-usage.Tests.ps1` with fixed-time fixtures. The tests must cover the normal dual-window response and the live single-weekly-window shape observed on this machine.

```powershell
$scriptPath = Join-Path $PSScriptRoot "..\codex-usage.ps1"
. $scriptPath -LibraryOnly

function New-TestWindow {
  param(
    [int]$UsedPercent,
    [AllowNull()][long]$ResetsAt,
    [AllowNull()][long]$WindowDurationMins
  )

  [pscustomobject]@{
    usedPercent = $UsedPercent
    resetsAt = $ResetsAt
    windowDurationMins = $WindowDurationMins
  }
}

Describe "Format-ResetCountdown" {
  $now = [DateTimeOffset]::Parse("2026-07-27T12:00:00Z")

  It "formats day and hour units without spaces" {
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + (6 * 86400) + (20 * 3600)) -Now $now | Should Be "6d20h"
  }

  It "formats hour and minute units" {
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() + (2 * 3600) + (30 * 60)) -Now $now | Should Be "2h30m"
  }

  It "handles null and elapsed resets" {
    Format-ResetCountdown -ResetAt $null -Now $now | Should Be "--"
    Format-ResetCountdown -ResetAt ($now.ToUnixTimeSeconds() - 1) -Now $now | Should Be "now"
  }
}

Describe "ConvertTo-CodexUsageOutput" {
  $now = [DateTimeOffset]::Parse("2026-07-27T12:00:00Z")

  It "uses a seven-day secondary window for the weekly label" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 12 ($now.ToUnixTimeSeconds() + 9000) 300
      secondary = New-TestWindow 34 ($now.ToUnixTimeSeconds() + 590400) 10080
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now

    $result.label | Should Be "34%/6d20h"
    $result.weekly_percent | Should Be 34
    $result.primary_percent | Should Be 12
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
    $result.tooltip | Should Be "Weekly: 6% (resets in 6d)"
  }

  It "labels a nonstandard secondary duration explicitly" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 10 ($now.ToUnixTimeSeconds() + 3600) 300
      secondary = New-TestWindow 44 ($now.ToUnixTimeSeconds() + 90000) 2880
    }

    $result = ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now
    $result.tooltip | Should Match "Usage \(2d\): 44%"
  }

  It "rejects a response with no weekly window" {
    $limits = [pscustomobject]@{
      primary = New-TestWindow 10 ($now.ToUnixTimeSeconds() + 3600) 300
      secondary = $null
    }

    { ConvertTo-CodexUsageOutput -RateLimits $limits -Now $now } | Should Throw "weekly usage window"
  }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
pwsh -NoProfile -NonInteractive -Command '$result = Invoke-Pester -Script Windows/Yasb/tests/codex-usage.Tests.ps1 -PassThru; if ($result.FailedCount -gt 0) { exit 1 }'
```

Expected: FAIL because `Windows/Yasb/codex-usage.ps1` does not exist.

- [ ] **Step 3: Implement the minimal pure functions**

Create `Windows/Yasb/codex-usage.ps1` with this entry-point contract and the pure functions required by the tests:

```powershell
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
  param([AllowNull()][object]$DurationMinutes, [switch]$Secondary)

  if ($null -eq $DurationMinutes) { return $(if ($Secondary) { "Usage" } else { "Session" }) }
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

  if ($null -eq $RateLimits.primary) { throw "Codex did not return a primary usage window." }

  $primary = $RateLimits.primary
  $weekly = $RateLimits.secondary
  $mirrorPrimary = $false
  if ($null -eq $weekly) {
    if ($null -ne $primary.windowDurationMins -and (Test-ApproximateDuration ([long]$primary.windowDurationMins) 10080)) {
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
```

- [ ] **Step 4: Run the test and verify GREEN**

Run the Pester command from Step 2.

Expected: all normalization and countdown tests PASS with `FailedCount: 0`.

- [ ] **Step 5: Commit the pure logic**

```powershell
git add -- Windows/Yasb/codex-usage.ps1 Windows/Yasb/tests/codex-usage.Tests.ps1
git commit -m "feat(yasb): normalize Codex usage limits"
```

### Task 2: Safe Cache Fallback

**Files:**
- Modify: `Windows/Yasb/codex-usage.ps1`
- Modify: `Windows/Yasb/tests/codex-usage.Tests.ps1`

- [ ] **Step 1: Add failing cache tests**

Append this test block:

```powershell
Describe "Codex usage cache fallback" {
  It "returns cached normalized data marked stale" {
    $cachePath = Join-Path $TestDrive "codex-usage.json"
    $cached = [ordered]@{
      label = "21%/4d3h"
      weekly_percent = 21
      weekly_reset = "4d3h"
      primary_percent = 8
      primary_reset = "2h"
      tooltip = "Session: 8% (resets in 2h)`nWeekly: 21% (resets in 4d3h)"
      stale = $false
    }
    [IO.File]::WriteAllText($cachePath, ($cached | ConvertTo-Json -Compress))
    [IO.File]::SetLastWriteTimeUtc($cachePath, [datetime]::Parse("2026-07-27T11:00:00Z").ToUniversalTime())

    $result = Get-CodexUsageFallback -ErrorMessage "request timed out" -CachePath $cachePath -Now ([DateTimeOffset]::Parse("2026-07-27T12:00:00Z"))

    $result.label | Should Be "21%/4d3h"
    $result.stale | Should Be $true
    $result.tooltip | Should Match "Stale \(1h old\): request timed out"
  }

  It "returns a valid unavailable object when no cache exists" {
    $cachePath = Join-Path $TestDrive "missing.json"
    $result = Get-CodexUsageFallback -ErrorMessage "not logged in" -CachePath $cachePath

    $result.label | Should Be "Codex ?"
    $result.tooltip | Should Be "Codex usage unavailable: not logged in"
    $result.stale | Should Be $true
  }

  It "ignores a malformed cache" {
    $cachePath = Join-Path $TestDrive "invalid.json"
    [IO.File]::WriteAllText($cachePath, "not-json")

    $result = Get-CodexUsageFallback -ErrorMessage "refresh failed" -CachePath $cachePath
    $result.label | Should Be "Codex ?"
  }
}
```

- [ ] **Step 2: Run Pester and verify RED**

Run the Task 1 Pester command.

Expected: FAIL because `Get-CodexUsageFallback` is undefined.

- [ ] **Step 3: Implement normalized cache writes and fallback reads**

Add these functions before the script entry point:

```powershell
function Format-CacheAge {
  param([TimeSpan]$Age)

  if ($Age.TotalMinutes -lt 1) { return "just now" }
  if ($Age.TotalHours -lt 1) { return "$([math]::Floor($Age.TotalMinutes))m old" }
  if ($Age.TotalDays -lt 1) { return "$([math]::Floor($Age.TotalHours))h old" }
  "$([math]::Floor($Age.TotalDays))d old"
}

function Write-CodexUsageCache {
  param([Parameter(Mandatory)][psobject]$Output, [Parameter(Mandatory)][string]$CachePath)

  $directory = Split-Path -Parent $CachePath
  if (-not [IO.Directory]::Exists($directory)) { $null = [IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = "$CachePath.$PID.tmp"
  try {
    [IO.File]::WriteAllText($temporaryPath, ($Output | ConvertTo-Json -Compress -Depth 6))
    [IO.File]::Move($temporaryPath, $CachePath, $true)
  } finally {
    if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
  }
}

function Get-CodexUsageFallback {
  param(
    [Parameter(Mandatory)][string]$ErrorMessage,
    [Parameter(Mandatory)][string]$CachePath,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )

  $reason = ($ErrorMessage -replace "[\r\n]+", " ").Trim()
  if ($reason.Length -gt 160) { $reason = $reason.Substring(0, 160) }
  if ([IO.File]::Exists($CachePath)) {
    try {
      $cached = [IO.File]::ReadAllText($CachePath) | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace([string]$cached.label) -or [string]::IsNullOrWhiteSpace([string]$cached.tooltip)) {
        throw "Cache is missing required fields."
      }
      $age = $Now - [DateTimeOffset]([IO.File]::GetLastWriteTimeUtc($CachePath))
      $cached.tooltip = "Stale ($(Format-CacheAge $age)): $reason`n$($cached.tooltip)"
      $cached.stale = $true
      return $cached
    } catch {
      # A malformed cache is equivalent to no cache; never emit invalid JSON.
    }
  }

  [ordered]@{
    label = "Codex ?"
    weekly_percent = $null
    weekly_reset = "--"
    primary_percent = $null
    primary_reset = "--"
    tooltip = "Codex usage unavailable: $reason"
    stale = $true
  }
}
```

- [ ] **Step 4: Run Pester and verify GREEN**

Run the Task 1 Pester command.

Expected: all tests PASS with `FailedCount: 0`.

- [ ] **Step 5: Commit cache behavior**

```powershell
git add -- Windows/Yasb/codex-usage.ps1 Windows/Yasb/tests/codex-usage.Tests.ps1
git commit -m "feat(yasb): cache Codex usage output"
```

### Task 3: Codex App-Server Exchange

**Files:**
- Modify: `Windows/Yasb/codex-usage.ps1`

- [ ] **Step 1: Run the missing-entry-point integration check**

Run:

```powershell
pwsh -NoProfile -NonInteractive -File Windows/Yasb/codex-usage.ps1 | ConvertFrom-Json
```

Expected: FAIL because the script loads functions but emits no JSON yet.

- [ ] **Step 2: Add the bounded JSONL exchange and script entry point**

Add these functions after cache handling:

```powershell
function Read-AppServerResponse {
  param(
    [Parameter(Mandatory)][Diagnostics.Process]$Process,
    [Parameter(Mandatory)][int]$ResponseId,
    [Parameter(Mandatory)][DateTimeOffset]$Deadline
  )

  while ([DateTimeOffset]::UtcNow -lt $Deadline) {
    $remainingMs = [math]::Max(1, [int]($Deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
    $readTask = $Process.StandardOutput.ReadLineAsync()
    if (-not $readTask.Wait($remainingMs)) { throw "Codex app-server timed out." }
    $line = $readTask.Result
    if ($null -eq $line) { throw "Codex app-server closed before response $ResponseId." }
    try { $message = $line | ConvertFrom-Json } catch { continue }
    $idProperty = $message.PSObject.Properties["id"]
    if ($null -eq $idProperty -or $idProperty.Value -ne $ResponseId) { continue }
    $errorProperty = $message.PSObject.Properties["error"]
    if ($null -ne $errorProperty -and $null -ne $errorProperty.Value) {
      throw "Codex app-server error: $($errorProperty.Value.message)"
    }
    return $message
  }
  throw "Codex app-server timed out."
}

function Invoke-CodexRateLimits {
  param([ValidateRange(1, 120)][int]$TimeoutSeconds = 15)

  $startInfo = [Diagnostics.ProcessStartInfo]::new("codex")
  $startInfo.ArgumentList.Add("app-server")
  $startInfo.ArgumentList.Add("--stdio")
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  $started = $false

  try {
    $started = $process.Start()
    if (-not $started) { throw "Could not start Codex app-server." }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $initialize = [ordered]@{
      method = "initialize"
      id = 0
      params = @{ clientInfo = @{ name = "yasb_codex_usage"; title = "YASB Codex Usage"; version = "1" } }
    }
    $process.StandardInput.WriteLine(($initialize | ConvertTo-Json -Compress -Depth 8))
    $process.StandardInput.Flush()
    $null = Read-AppServerResponse -Process $process -ResponseId 0 -Deadline $deadline

    $process.StandardInput.WriteLine((@{ method = "initialized"; params = @{} } | ConvertTo-Json -Compress))
    $process.StandardInput.WriteLine((@{ method = "account/rateLimits/read"; id = 1; params = @{} } | ConvertTo-Json -Compress))
    $process.StandardInput.Flush()
    $response = Read-AppServerResponse -Process $process -ResponseId 1 -Deadline $deadline
    if ($null -eq $response.result.rateLimits) { throw "Codex app-server returned no rate limits." }
    $response.result.rateLimits
  } finally {
    if ($started) {
      try { $process.StandardInput.Close() } catch {}
      if (-not $process.HasExited) { try { $process.Kill($true) } catch {} }
      try { $process.WaitForExit(2000) } catch {}
    }
    $process.Dispose()
  }
}
```

Add this final entry point at the bottom of the script:

```powershell
if (-not $LibraryOnly) {
  try {
    $rateLimits = Invoke-CodexRateLimits -TimeoutSeconds $TimeoutSeconds
    $output = ConvertTo-CodexUsageOutput -RateLimits $rateLimits
    Write-CodexUsageCache -Output $output -CachePath $CachePath
  } catch {
    $output = Get-CodexUsageFallback -ErrorMessage $_.Exception.Message -CachePath $CachePath
  }
  $output | ConvertTo-Json -Compress -Depth 6
}
```

- [ ] **Step 3: Run unit and live integration checks**

Run:

```powershell
pwsh -NoProfile -NonInteractive -Command '$result = Invoke-Pester -Script Windows/Yasb/tests/codex-usage.Tests.ps1 -PassThru; if ($result.FailedCount -gt 0) { exit 1 }'
pwsh -NoProfile -NonInteractive -Command '$result = & ./Windows/Yasb/codex-usage.ps1 | ConvertFrom-Json; if ($result.label -notmatch "^(Codex \?|[0-9]+%/(now|<1m|[0-9]+[dhm].*))$") { throw "Unexpected label: $($result.label)" }; $result | ConvertTo-Json -Compress'
```

Expected: Pester reports zero failures. The live command emits exactly one JSON object; on the currently authenticated machine it contains a numeric weekly label, `stale:false`, and no access token or account id.

- [ ] **Step 4: Inspect the normalized cache**

Run:

```powershell
pwsh -NoProfile -NonInteractive -Command '$path = Join-Path $env:LOCALAPPDATA "yasb\codex-usage.json"; $cache = [IO.File]::ReadAllText($path) | ConvertFrom-Json; $names = @($cache.PSObject.Properties.Name); $allowed = @("label", "weekly_percent", "weekly_reset", "primary_percent", "primary_reset", "tooltip", "stale"); if (@($names | Where-Object { $_ -notin $allowed }).Count -gt 0) { throw "Unexpected cache fields" }; $names -join ","'
```

Expected: only the seven normalized field names are printed.

- [ ] **Step 5: Commit the app-server adapter**

```powershell
git add -- Windows/Yasb/codex-usage.ps1 Windows/Yasb/tests/codex-usage.Tests.ps1
git commit -m "feat(yasb): query Codex usage through app server"
```

### Task 4: YASB Widget And Tidydots Mapping

**Files:**
- Modify: `Windows/Yasb/config.yaml:35-68`
- Modify: `Windows/Yasb/styles.css:37-50`
- Modify: `tidydots.yaml:282-289`

- [ ] **Step 1: Run a failing configuration assertion**

Run:

```powershell
python -c "import yaml; c=yaml.safe_load(open('Windows/Yasb/config.yaml', encoding='utf-8')); assert c['widgets']['codex_usage']['type'] == 'yasb.custom.CustomWidget'; assert c['bars']['primary-bar']['widgets']['right'][0] == 'codex_usage'"
```

Expected: FAIL with `KeyError: 'codex_usage'`.

- [ ] **Step 2: Add the widget to the right-side bar and widget map**

Update the right-side comment/list and add this definition before `clock`:

```yaml
      # Right: Codex usage, systray, volume, disk, memory, cpu
      right:
        - "codex_usage"
        - "systray"
        - "volume"
        - "disk"
        - "memory"
        - "cpu"
widgets:
  codex_usage:
    type: "yasb.custom.CustomWidget"
    options:
      label: "{data[label]}"
      label_placeholder: "Codex..."
      class_name: "codex-usage-widget"
      tooltip: true
      tooltip_label: "{data[tooltip]}"
      exec_options:
        # Decodes to: & (Join-Path $env:USERPROFILE '.config\yasb\codex-usage.ps1')
        run_cmd: "pwsh.exe -NoProfile -NonInteractive -EncodedCommand JgAgACgASgBvAGkAbgAtAFAAYQB0AGgAIAAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFACAAJwAuAGMAbwBuAGYAaQBnAFwAeQBhAHMAYgBcAGMAbwBkAGUAeAAtAHUAcwBhAGcAZQAuAHAAcwAxACcAKQA="
        run_interval: 300000
        return_format: "json"
        hide_empty: false
        use_shell: true
      callbacks:
        on_left: "exec cmd.exe /c start https://chatgpt.com/codex/settings/usage"
        on_middle: "do_nothing"
        on_right: "do_nothing"
```

Preserve the existing commented optional widgets instead of deleting them.

- [ ] **Step 3: Add neutral dim styling**

Add after the global widget defaults:

```css
/* ==================== Codex Usage ==================== */
.codex-usage-widget {
  margin-right: 10px;
}
.codex-usage-widget .label {
  color: var(--text-dim);
}
```

- [ ] **Step 4: Add the helper to the YASB tidydots file list**

Add only this line beneath `styles.css` in the existing YASB entry:

```yaml
          - codex-usage.ps1
```

In the isolated worktree, keep this as the only `tidydots.yaml` change.

- [ ] **Step 5: Validate YAML and tidydots without changing the system**

Run:

```powershell
python -c "import base64, yaml; c=yaml.safe_load(open('Windows/Yasb/config.yaml', encoding='utf-8')); e=c['widgets']['codex_usage']['options']['exec_options']; p='JgAgACgASgBvAGkAbgAtAFAAYQB0AGgAIAAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFACAAJwAuAGMAbwBuAGYAaQBnAFwAeQBhAHMAYgBcAGMAbwBkAGUAeAAtAHUAcwBhAGcAZQAuAHAAcwAxACcAKQA='; d='& (Join-Path `$env:USERPROFILE ' + chr(39) + '.config\\yasb\\codex-usage.ps1' + chr(39) + ')'; assert c['widgets']['codex_usage']['type'] == 'yasb.custom.CustomWidget'; assert c['bars']['primary-bar']['widgets']['right'][0] == 'codex_usage'; assert e['run_cmd'] == 'pwsh.exe -NoProfile -NonInteractive -EncodedCommand ' + p; assert base64.b64decode(p).decode('utf-16le') == d; assert e['run_interval'] == 300000"
tidydots --dir . list
tidydots --dir . restore -n
```

Expected: YAML assertions exit zero, including exact `run_cmd` and decoded-command checks; `tidydots --dir . list` parses the worktree's v3 configuration; `tidydots --dir . restore -n` includes `codex-usage.ps1` under the Windows YASB target and makes no filesystem changes. Ignore unrelated dry-run entries that predate this feature.

- [ ] **Step 6: Commit files without unrelated working-tree changes**

Inspect `git status --short` and `git diff` first. In the isolated worktree, commit the widget configuration, styling, and helper mapping together:

```powershell
git commit --only Windows/Yasb/config.yaml Windows/Yasb/styles.css tidydots.yaml -m "feat(yasb): display Codex usage"
```

The feature mapping in `tidydots.yaml` is committed on this branch. During integration, preserve any unrelated `tidydots.yaml` changes that remain in the main checkout.

### Task 5: Deployment And End-To-End Verification

**Files:**
- Verify: `Windows/Yasb/codex-usage.ps1`
- Verify: `Windows/Yasb/config.yaml`
- Verify: `Windows/Yasb/styles.css`
- Verify: `tidydots.yaml`

- [ ] **Step 1: Run the complete repository-side verification**

Run:

```powershell
pwsh -NoProfile -NonInteractive -Command '$result = Invoke-Pester -Script Windows/Yasb/tests/codex-usage.Tests.ps1 -PassThru; if ($result.FailedCount -gt 0) { exit 1 }'
python -c "import yaml; yaml.safe_load(open('Windows/Yasb/config.yaml', encoding='utf-8')); yaml.safe_load(open('tidydots.yaml', encoding='utf-8'))"
pwsh -NoProfile -NonInteractive -Command '$lines = @(& ./Windows/Yasb/codex-usage.ps1); if ($lines.Count -ne 1) { throw "Expected one JSON line, got $($lines.Count)" }; $value = $lines[0] | ConvertFrom-Json; if ([string]::IsNullOrWhiteSpace($value.label) -or [string]::IsNullOrWhiteSpace($value.tooltip)) { throw "Missing widget output" }'
tidydots --dir . list
tidydots --dir . restore -n
git diff --check
```

Expected: Pester has zero failures, both YAML files parse, helper emits one valid JSON line, worktree-scoped tidydots list and dry-run show only planned changes, and `git diff --check` emits no errors.

- [ ] **Step 2: Show the dry-run and obtain confirmation before restore**

Summarize the `tidydots --dir . restore -n` YASB changes to the user. Do not run a real restore until the branch is integrated into main and the user explicitly confirms it, as required by the repository's tidydots safety workflow.

- [ ] **Step 3: Restore after confirmation and verify the deployed helper**

After the branch is integrated, switch to the main checkout. After explicit confirmation, run there:

```powershell
tidydots restore
pwsh -NoProfile -NonInteractive -Command '$path = Join-Path $HOME ".config\yasb\codex-usage.ps1"; if (-not (Test-Path -LiteralPath $path)) { throw "Helper was not deployed" }; & $path | ConvertFrom-Json | Select-Object label, stale, tooltip'
```

Expected: main's integrated tidydots configuration deploys the helper and the deployed command returns a populated object.

- [ ] **Step 4: Reload YASB and inspect runtime logs**

Run:

```powershell
yasbc reload
```

Then run `yasbc log` with a five-second command timeout, capture one refresh cycle, and confirm there is no custom-widget parse or command error.

Expected: the bar reloads with a dim `<percentage>%/<reset>` Codex label before the systray. Hover shows usage details, and left-click opens the Codex usage page.

- [ ] **Step 5: Report final status and residual constraints**

Report the exact verification outputs, note that the feature's `tidydots.yaml` mapping was committed on the feature branch, preserve any unrelated main-checkout changes during integration, and state that the integration depends on the experimental Codex app-server protocol available in Codex CLI 0.145.0.
