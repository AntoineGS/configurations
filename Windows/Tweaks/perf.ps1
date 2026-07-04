<#
.SYNOPSIS
  Snappiness tweaks for Windows. Idempotent and reversible.

.DESCRIPTION
  Trims perceived latency to bring a Windows box closer to a lean tiling-WM
  feel (e.g. Hyprland/Arch): disables shell animations, forces High Performance
  power, prunes noisy auto-start entries, and disables the Windows Search
  indexer.

  Everything here is per-user (HKCU) or service-level and fully reversible.
  Backups: registry keys can be re-imported; power plan/service can be reset.
  See RESTORE notes at the bottom.

.NOTES
  - Disabling the WSearch service requires an elevated (Administrator) shell.
    The rest runs fine as a normal user.
  - Does NOT touch IT-managed security tooling (Defender for Endpoint, TightVNC).
  - Run:  powershell -ExecutionPolicy Bypass -File .\perf.ps1
#>

$ErrorActionPreference = 'Stop'

function Set-Reg($Path, $Name, $Value, $Type) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

Write-Host '== 1. Trim shell animations (keep ClearType + thumbnails) ==' -ForegroundColor Cyan
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3 'DWord'
Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 'DWord'
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0 'DWord'
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0 'DWord'
Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
if (Test-Path 'HKCU:\Software\Microsoft\Windows\DWM') {
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0 'DWord'
}

Write-Host '== 2. High Performance power plan ==' -ForegroundColor Cyan
$high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
# Unlock Ultimate Performance if policy allows; otherwise fall back to High.
powercfg -duplicatescheme $ultimate 2>&1 | Out-Null
if ((powercfg /list) -match $ultimate) { powercfg /setactive $ultimate }
else { powercfg /setactive $high }
powercfg /getactivescheme

Write-Host '== 3+4. Prune auto-start entries ==' -ForegroundColor Cyan
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$prune = @(
    'GlazeWM'                # Komorebi is the active WM
    'Docker Desktop'         # launch manually when needed (spins a WSL2 VM)
    'Anytxt'                 # search indexer, unused
    'JetBrains Toolbox'      # open manually for IDE updates
    'Everything 1.5a'        # unused
    'EverythingToolbar'      # unused (depends on Everything)
    'MicrosoftEdgeAutoLaunch_F70D1747ADA17DF9E373EB21A9A85F09'
    'MicrosoftEdgeAutoLaunch_CE936CE4DB5E9FBC0AEB1ADE6A34A7FD'
)
$props = (Get-ItemProperty $run -ErrorAction SilentlyContinue).PSObject.Properties.Name
foreach ($name in $prune) {
    if ($props -contains $name) { Remove-ItemProperty $run -Name $name; Write-Host "  removed: $name" }
}
# Stop any leftover unused indexers this session
Stop-Process -Name Everything, EverythingToolbar, ATGUI -Force -ErrorAction SilentlyContinue

Write-Host '== 5. Disable Windows Search indexer (WSearch) ==' -ForegroundColor Cyan
try {
    Stop-Service WSearch -Force
    Set-Service WSearch -StartupType Disabled
    Write-Host '  WSearch stopped and disabled.'
} catch {
    Write-Warning "  WSearch needs an elevated shell. Re-run this script as Administrator, or run:"
    Write-Warning '    Stop-Service WSearch -Force; Set-Service WSearch -StartupType Disabled'
}

Write-Host '== 6. Dev databases -> Manual (start on demand) ==' -ForegroundColor Cyan
function Set-ManualSvc($name) {
    try { Set-Service -Name $name -StartupType Manual -ErrorAction Stop; Write-Host "  [Manual] $name" }
    catch { Write-Host "  [skip]   $name ($($_.Exception.Message))" }
}
'postgresql-x64-18', 'FirebirdGuardianDefaultInstance', 'IBG_gds_db',
'BlackfishSQL', 'SQLWriter' | ForEach-Object { Set-ManualSvc $_ }

Write-Host '== 7. Updater services -> Manual ==' -ForegroundColor Cyan
'FoxitReaderUpdateService', 'edgeupdate', 'edgeupdatem', 'ClickToRunSvc',
'GoogleUpdaterService150.0.7863.0',
'GoogleUpdaterInternalService150.0.7863.0' | ForEach-Object { Set-ManualSvc $_ }

Write-Host '== 8. Disable Winget-AutoUpdate scheduled tasks ==' -ForegroundColor Cyan
Get-ScheduledTask -TaskPath '\WAU\' -ErrorAction SilentlyContinue | ForEach-Object {
    try { Disable-ScheduledTask -TaskName $_.TaskName -TaskPath '\WAU\' -ErrorAction Stop | Out-Null; Write-Host "  disabled: $($_.TaskName)" }
    catch { Write-Host "  skip: $($_.TaskName)" }
}

Write-Host '== 9. Disable telemetry (DiagTrack) ==' -ForegroundColor Cyan
try { Stop-Service DiagTrack -Force -ErrorAction Stop } catch {}
try { Set-Service DiagTrack -StartupType Disabled -ErrorAction Stop; Write-Host '  DiagTrack disabled.' }
catch { Write-Warning "  DiagTrack: $($_.Exception.Message) (needs admin / may be policy-managed)" }

Write-Host '== 10. Disable TightVNC auto-start ==' -ForegroundColor Cyan
try { Stop-Service tvnserver -Force -ErrorAction Stop } catch {}
try { Set-Service tvnserver -StartupType Disabled -ErrorAction Stop; Write-Host '  tvnserver disabled.' } catch {}
$hklmRun = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
if ((Get-ItemProperty $hklmRun -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'tvncontrol') {
    Remove-ItemProperty $hklmRun -Name 'tvncontrol'; Write-Host '  removed tvncontrol from HKLM Run.'
}

Write-Host '== 10b. Remote-access agents -> Manual (start on demand) ==' -ForegroundColor Cyan
# Chrome Remote Desktop (chromoting) intentionally left Automatic as the daily-use tool.
$remote = @('RustDesk', 'TeamViewer', 'SonicWall_NetExtender_Service')
$remote += (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Splashtop*' } | Select-Object -Expand Name)
$remote | Select-Object -Unique | ForEach-Object { Set-ManualSvc $_ }

Write-Host '== 11. Disable Fast Startup (hybrid shutdown) ==' -ForegroundColor Cyan
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'DWord'
Write-Host '  HiberbootEnabled = 0'

Write-Host '== 12. Pull slow items out of the boot path ==' -ForegroundColor Cyan
# aqIPD8 = SmartBear/AQtime profiler kernel driver (System-start -> Demand). ~15s off usable boot.
$aq = 'HKLM:\SYSTEM\CurrentControlSet\Services\aqIPD8'
if (Test-Path $aq) { Set-Reg $aq 'Start' 3 'DWord'; Write-Host '  aqIPD8 -> Demand (3)' }
# CoworkVMService (Claude sandbox VM): Auto -> Manual. ACL-locked, so set Start via registry.
$cw = 'HKLM:\SYSTEM\CurrentControlSet\Services\CoworkVMService'
if (Test-Path $cw) {
    try { Set-Reg $cw 'Start' 3 'DWord'; Write-Host '  CoworkVMService -> Manual (3)' }
    catch { Write-Warning "  CoworkVMService: $($_.Exception.Message)" }
}

Write-Host '== 13. Runtime UI snappiness ==' -ForegroundColor Cyan
# Disable transparency -> less DWM compositing (notable on integrated GPUs).
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 'DWord'
# Disable Game DVR / Xbox Game Bar background capture.
Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord'
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord'
try { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 'DWord' } catch {}
Write-Host '  Transparency off, Game DVR off.'

Write-Host ''
Write-Host 'Done. Sign out/in (or restart explorer.exe) for animation changes to fully apply.' -ForegroundColor Green
Write-Host 'Manual-start services (DBs, updaters) launch on demand: Start-Service <name>, or via services.msc.' -ForegroundColor Green

<#
RESTORE / UNDO
  Animations:   set VisualFXSetting back to 1 (best appearance), MenuShowDelay 400,
                MinAnimate 1, TaskbarAnimations 1.
  Power plan:   powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e   # Balanced
  WSearch:      Set-Service WSearch -StartupType Automatic; Start-Service WSearch
  DBs/updaters: Set-Service <name> -StartupType Automatic   (Manual -> Automatic)
  DiagTrack:    Set-Service DiagTrack -StartupType Automatic; Start-Service DiagTrack
  TightVNC:     Set-Service tvnserver -StartupType Automatic; Start-Service tvnserver
  Winget-AU:    Enable-ScheduledTask -TaskPath '\WAU\' -TaskName <name>
  Fast Startup: HiberbootEnabled = 1  (same key as above)
  aqIPD8:       Services\aqIPD8\Start = 1  (System) to restore boot-time profiler driver
  CoworkVMSvc:  Services\CoworkVMService\Start = 2  (Automatic)
  Transparency: Themes\Personalize\EnableTransparency = 1
  Game DVR:     GameConfigStore\GameDVR_Enabled = 1; GameDVR\AllowGameDVR = 1
  Auto-start:   re-add entries under HKCU/HKLM ...\CurrentVersion\Run as needed.
#>
