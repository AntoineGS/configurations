[CmdletBinding()]
param(
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RegistrySubKeyPath = 'SOFTWARE\OpenSSH'
$ProgramFilesRegistrySubKeyPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion'
$ProgramFilesRegistryValueName = 'ProgramFilesDir'

function Get-TrustedProgramFilesRoot {
  [CmdletBinding()]
  param(
    [switch]$Required
  )

  $baseKey = $null
  $currentVersionKey = $null
  $invalidReason = $null
  $programFilesRoot = $null
  try {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
      [Microsoft.Win32.RegistryHive]::LocalMachine,
      [Microsoft.Win32.RegistryView]::Registry64
    )
    $currentVersionKey = $baseKey.OpenSubKey($ProgramFilesRegistrySubKeyPath, $false)
    if ($null -eq $currentVersionKey) {
      $invalidReason = "the key '$ProgramFilesRegistrySubKeyPath' is missing"
    } else {
      $valueNames = $currentVersionKey.GetValueNames()
      if ($valueNames -notcontains $ProgramFilesRegistryValueName) {
        $invalidReason = "the value '$ProgramFilesRegistryValueName' is missing"
      } elseif ($currentVersionKey.GetValueKind($ProgramFilesRegistryValueName) -ne [Microsoft.Win32.RegistryValueKind]::String) {
        $invalidReason = "the value '$ProgramFilesRegistryValueName' is not a REG_SZ string"
      } else {
        $programFilesRoot = $currentVersionKey.GetValue(
          $ProgramFilesRegistryValueName,
          $null,
          [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
        if (
          $programFilesRoot -isnot [string] -or
          [string]::IsNullOrWhiteSpace([string]$programFilesRoot) -or
          -not [IO.Path]::IsPathRooted([string]$programFilesRoot)
        ) {
          $invalidReason = "the value '$ProgramFilesRegistryValueName' is not a nonempty absolute path"
        }
      }
    }

    if ($null -eq $invalidReason) {
      return [string]$programFilesRoot
    }
    if ($Required) {
      throw "The protected 64-bit Program Files registry value is invalid: $invalidReason."
    }
    return $null
  } finally {
    if ($null -ne $currentVersionKey) {
      $currentVersionKey.Dispose()
    }
    if ($null -ne $baseKey) {
      $baseKey.Dispose()
    }
  }
}

$ProgramFilesRoot = if ($Check) {
  Get-TrustedProgramFilesRoot
} else {
  Get-TrustedProgramFilesRoot -Required
}
$DefaultShellPath = if ([string]::IsNullOrWhiteSpace($ProgramFilesRoot)) {
  $null
} else {
  Join-Path $ProgramFilesRoot 'PowerShell\7\pwsh.exe'
}
$DefaultShellCommandOption = '-c'

function Test-PowerShellOpenSshState {
  [CmdletBinding()]
  param()

  if ([string]::IsNullOrWhiteSpace($DefaultShellPath) -or -not (Test-Path -LiteralPath $DefaultShellPath -PathType Leaf)) {
    return $false
  }

  $baseKey = $null
  $openSshKey = $null
  try {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
      [Microsoft.Win32.RegistryHive]::LocalMachine,
      [Microsoft.Win32.RegistryView]::Registry64
    )
    $openSshKey = $baseKey.OpenSubKey($RegistrySubKeyPath, $false)
    if ($null -eq $openSshKey) {
      return $false
    }

    $valueNames = $openSshKey.GetValueNames()
    if ($valueNames -notcontains 'DefaultShell' -or $valueNames -notcontains 'DefaultShellCommandOption') {
      return $false
    }

    if (
      $openSshKey.GetValueKind('DefaultShell') -ne [Microsoft.Win32.RegistryValueKind]::String -or
      $openSshKey.GetValueKind('DefaultShellCommandOption') -ne [Microsoft.Win32.RegistryValueKind]::String
    ) {
      return $false
    }

    $shellValue = $openSshKey.GetValue(
      'DefaultShell',
      $null,
      [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )
    $optionValue = $openSshKey.GetValue(
      'DefaultShellCommandOption',
      $null,
      [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )

    return (
      [string]::Equals(
        [string]$shellValue,
        $DefaultShellPath,
        [StringComparison]::OrdinalIgnoreCase
      ) -and
      [string]::Equals(
        [string]$optionValue,
        $DefaultShellCommandOption,
        [StringComparison]::Ordinal
      )
    )
  } finally {
    if ($null -ne $openSshKey) {
      $openSshKey.Dispose()
    }
    if ($null -ne $baseKey) {
      $baseKey.Dispose()
    }
  }
}

function Test-IsAdministrator {
  [CmdletBinding()]
  param()

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-PowerShellOpenSshState {
  [CmdletBinding()]
  param()

  $baseKey = $null
  $openSshKey = $null
  try {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
      [Microsoft.Win32.RegistryHive]::LocalMachine,
      [Microsoft.Win32.RegistryView]::Registry64
    )
    $openSshKey = $baseKey.CreateSubKey($RegistrySubKeyPath)
    if ($null -eq $openSshKey) {
      throw "Could not open $RegistrySubKeyPath for writing."
    }

    $openSshKey.SetValue(
      'DefaultShell',
      $DefaultShellPath,
      [Microsoft.Win32.RegistryValueKind]::String
    )
    $openSshKey.SetValue(
      'DefaultShellCommandOption',
      $DefaultShellCommandOption,
      [Microsoft.Win32.RegistryValueKind]::String
    )
  } finally {
    if ($null -ne $openSshKey) {
      $openSshKey.Dispose()
    }
    if ($null -ne $baseKey) {
      $baseKey.Dispose()
    }
  }
}

function ConvertTo-PowerShellSingleQuotedLiteral {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Value
  )

  $escapedValue = $Value.Replace("'", "''")
  return "'" + $escapedValue + "'"
}

function New-ElevatedRegistryUpdateCommand {
  [CmdletBinding()]
  param()

  $shellLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value $DefaultShellPath
  $optionLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value $DefaultShellCommandOption
  $lines = @(
    '$ErrorActionPreference = "Stop"'
    '$baseKey = $null'
    '$openSshKey = $null'
    'try {'
    '  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey('
    '    [Microsoft.Win32.RegistryHive]::LocalMachine,'
    '    [Microsoft.Win32.RegistryView]::Registry64'
    '  )'
    '  $openSshKey = $baseKey.CreateSubKey(''SOFTWARE\OpenSSH'')'
    '  if ($null -eq $openSshKey) {'
    '    throw "Could not open SOFTWARE\OpenSSH for writing."'
    '  }'
    "  `$openSshKey.SetValue('DefaultShell', $shellLiteral, [Microsoft.Win32.RegistryValueKind]::String)"
    "  `$openSshKey.SetValue('DefaultShellCommandOption', $optionLiteral, [Microsoft.Win32.RegistryValueKind]::String)"
    '} finally {'
    '  if ($null -ne $openSshKey) {'
    '    $openSshKey.Dispose()'
    '  }'
    '  if ($null -ne $baseKey) {'
    '    $baseKey.Dispose()'
    '  }'
    '}'
  )

  return ($lines -join [Environment]::NewLine)
}

function Invoke-ElevatedRegistryUpdate {
  [CmdletBinding()]
  param()

  $command = New-ElevatedRegistryUpdateCommand
  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $child = $null
  try {
    $child = Start-Process -FilePath $DefaultShellPath -ArgumentList @(
      '-NoProfile'
      '-NonInteractive'
      '-EncodedCommand'
      $encodedCommand
    ) -Verb RunAs -Wait -PassThru -ErrorAction Stop
  } catch {
    throw "Could not elevate OpenSSH configuration. UAC may have been canceled. $($_.Exception.Message)"
  }

  if ($null -eq $child) {
    throw 'Could not start elevated OpenSSH configuration. UAC may have been canceled.'
  }

  try {
    return [int]$child.ExitCode
  } finally {
    $child.Dispose()
  }
}

if ($Check) {
  if (Test-PowerShellOpenSshState) {
    exit 0
  }

  Write-Output "OpenSSH is not configured to use PowerShell at '$DefaultShellPath'."
  exit 1
}

if ([string]::IsNullOrWhiteSpace($DefaultShellPath) -or -not (Test-Path -LiteralPath $DefaultShellPath -PathType Leaf)) {
  throw "PowerShell 7 was not found at '$DefaultShellPath'. Install PowerShell 7 before configuring OpenSSH."
}

if (Test-PowerShellOpenSshState) {
  Write-Output "OpenSSH already uses PowerShell at '$DefaultShellPath'."
  exit 0
}

if (-not (Test-IsAdministrator)) {
  $childExitCode = Invoke-ElevatedRegistryUpdate
  $stateMatches = Test-PowerShellOpenSshState
  if ($childExitCode -ne 0) {
    Write-Error -ErrorAction Continue "Elevated OpenSSH update exited with code $childExitCode."
    exit $childExitCode
  }
  if (-not $stateMatches) {
    throw "OpenSSH registry settings did not verify at '$RegistrySubKeyPath'."
  }

  Write-Output "OpenSSH default shell set to '$DefaultShellPath'."
  exit 0
}

Set-PowerShellOpenSshState

if (-not (Test-PowerShellOpenSshState)) {
  throw "OpenSSH registry settings did not verify at '$RegistrySubKeyPath'."
}

Write-Output "OpenSSH default shell set to '$DefaultShellPath'."
