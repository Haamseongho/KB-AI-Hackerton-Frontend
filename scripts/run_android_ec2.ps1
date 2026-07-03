param(
  [string]$DeviceId = $env:DEVICE_ID,
  [string]$ApiBaseUrl = $(if ($env:API_BASE_URL) { $env:API_BASE_URL } else { "http://13.124.81.217:8080" }),
  [string]$WsBaseUrl = $(if ($env:WS_BASE_URL) { $env:WS_BASE_URL } else { "ws://13.124.81.217:8080" })
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error "flutter command not found. Install Flutter SDK and add it to PATH."
}

flutter pub get

$flutterArgs = @(
  "run",
  "--dart-define=API_BASE_URL=$ApiBaseUrl",
  "--dart-define=WS_BASE_URL=$WsBaseUrl"
)

if ($DeviceId) {
  $flutterArgs += @("-d", $DeviceId)
}

flutter @flutterArgs
