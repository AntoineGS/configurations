$scriptPath = Join-Path $PSScriptRoot "..\komorebi.ahk"
$source = Get-Content -LiteralPath $scriptPath -Raw

Describe "Komorebi session monitor refresh" {
  It "registers and unregisters the script window for WTS session notifications" {
    $source | Should Match 'WTSRegisterSessionNotification'
    $source | Should Match 'WTSUnRegisterSessionNotification'
    $source | Should Match 'OnMessage\(0x02B1,\s*OnWtsSessionChange\)'
  }

  It "handles only display-ready session transitions" {
    $source | Should Match (
      'if eventType != 0x1 && eventType != 0x3 && ' +
      'eventType != 0x8 && eventType != 0xF'
    )
  }

  It "debounces session transitions before restarting Komorebi" {
    $source | Should Match 'SetTimer\s+RestartKomorebiForDisplayChange,\s*-3000'
  }

  It "uses the guarded restart path for the manual hotkey" {
    $source | Should Match 'komorebiRestartInProgress'
    $source | Should Match '#\^k::RestartKomorebiForDisplayChange\(\)'
    $source | Should Match 'replace-configuration'
  }

  It "is valid AutoHotkey v2 syntax" {
    $autoHotkey = (Get-Command AutoHotkey.exe -ErrorAction Stop).Source
    & $autoHotkey /ErrorStdOut=UTF-8 /Validate $scriptPath
    $LASTEXITCODE | Should Be 0
  }
}
