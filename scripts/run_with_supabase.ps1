# Run or build Bismillah with cloud sync enabled.
# Credentials live in bismillah_constructions/secrets/dart_defines.json (gitignored).
param(
  [ValidateSet('run', 'build-apk', 'build-windows')]
  [string]$Action = 'run',
  [string]$Device
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'bismillah_constructions'
$defines = Join-Path $app 'secrets\dart_defines.json'

if (-not (Test-Path $defines)) {
  Write-Error @"
Missing $defines
Copy secrets\dart_defines.example.json to secrets\dart_defines.json and fill in your Supabase URL + anon key.
"@
}

Set-Location $app

$common = @('--dart-define-from-file=secrets/dart_defines.json')

switch ($Action) {
  'run' {
    if ($Device) {
      flutter run @common -d $Device
    } else {
      flutter run @common
    }
  }
  'build-apk' {
    flutter build apk --release @common
  }
  'build-windows' {
    flutter build windows --release @common
  }
}
