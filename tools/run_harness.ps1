# End-to-end check without the game or DSX installed.
#
# Copies the built exe into a throwaway folder with DisableAppCheck=true (so the
# worker starts without ForzaHorizon6.exe / DSX.exe running), starts a fake DSX
# listener, streams fake FH6 telemetry at it, and reports the packet rate reaching DSX.
#
#   powershell -ExecutionPolicy Bypass -File tools\run_harness.ps1
#   powershell -ExecutionPolicy Bypass -File tools\run_harness.ps1 -ExePath ...\backup_original\RacingDSX.exe
#
# Expected: ~30 packets/s (Config.DSXUpdateRateHz) with three instructions per
# packet. The pre-fix build gives ~419 packets/s with one instruction per packet.
# With -StopEarly the last packet must be the trigger release:
#   {"instructions":[{"type":1,"parameters":[0,1,0,0,0]},{"type":1,"parameters":[0,2,0,0,0]}]}

param(
    [string]$ExePath  = "$PSScriptRoot\..\RacingDSX_exe\RacingDSX.exe",
    [int]$RateHz      = 140,
    # Cut telemetry off early to exercise the FH6 "stream stops in menus" path.
    [switch]$StopEarly
)

$ErrorActionPreference = "Stop"
$root    = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path $env:TEMP "racingdsx_harness"
$drive   = if ($StopEarly) { 4 } else { 10 }
$listen  = $drive + 8

if (Get-Process RacingDSX -ErrorAction SilentlyContinue) {
    throw "RacingDSX is already running; close it first."
}
if (Get-NetUDPEndpoint -LocalPort 6969 -ErrorAction SilentlyContinue) {
    throw "UDP 6969 is busy (real DSX running?)."
}

Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
Copy-Item $ExePath $sandbox -Force
Copy-Item (Join-Path (Split-Path $ExePath -Parent) "RacingDSX.dll.config") $sandbox -Force -ErrorAction SilentlyContinue

# App check off, so the worker runs without the real game and DSX processes.
$cfg = Get-Content (Join-Path $root "RacingDSX_exe\RacingDSX.json") -Raw
$cfg = $cfg -replace '"DisableAppCheck":false', '"DisableAppCheck":true'
$cfg | Out-File -FilePath (Join-Path $sandbox "RacingDSX.json") -Encoding utf8 -NoNewline

Write-Output "sandbox: $sandbox"
Write-Output "exe:     $ExePath"

$capture = Join-Path $sandbox "capture.json"
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", "$PSScriptRoot\fake_dsx.ps1",
    "-Seconds", $listen, "-OutFile", $capture
)
Start-Sleep -Milliseconds 800

Start-Process -FilePath (Join-Path $sandbox "RacingDSX.exe") -WorkingDirectory $sandbox
Start-Sleep -Seconds 2

& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\fake_forza.ps1" -Seconds $drive -RateHz $RateHz

Start-Sleep -Seconds ($listen - $drive - 1)
Get-Process RacingDSX -ErrorAction SilentlyContinue | Stop-Process -Force

$rows = Get-Content $capture -Raw | ConvertFrom-Json
$window = $rows | Where-Object { $_.T -ge 3 -and $_.T -le ($drive + 1) }
Write-Output ""
Write-Output ("RESULT: {0} packets total, {1}/sec steady state" -f $rows.Count,
    [Math]::Round($window.Count / ($drive - 2), 1))
Write-Output "--- last 3 packets ---"
$rows | Select-Object -Last 3 | ForEach-Object { "{0,7}s  {1}" -f $_.T, $_.Json }
