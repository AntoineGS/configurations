[CmdletBinding()]
param(
  [ValidateSet('Attach')]
  [string]$Mode = 'Attach',

  [string]$HerdrPath
)

if ([string]::IsNullOrWhiteSpace($HerdrPath)) {
  $HerdrPath = (Get-Command herdr -ErrorAction Stop).Source
}

& $HerdrPath
