# Shows what the LEFT (brake) trigger receives for fixed brake / slip / locked-wheel inputs,
# and how many brief lock-ups make it through to DSX as vibration.
#
#   powershell -ExecutionPolicy Bypass -File tools\probe_brake.ps1
#   powershell -ExecutionPolicy Bypass -File tools\probe_brake.ps1 -ExePath RacingDSX_exe\backup_original\RacingDSX.exe
#
# Left-trigger params are [controller, 1=Left, mode, ...]:
#   mode 13 = Resistance, last number is force (0 = nothing)
#   mode 12 = CustomTriggerValue, next 9 = VibrateResistance, then frequency, stiffness
# The sandboxed exe uses its own ports (game 5310, DSX 6970), so the real DSX and RacingDSX
# can stay open. Takes about a minute. For real driving data use check_brake_replay.ps1.

param(
    [string]$ExePath = "",
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
$tools = Split-Path $MyInvocation.MyCommand.Path -Parent
if (-not $ExePath) { $ExePath = "$tools\..\RacingDSX_exe\RacingDSX.exe" }
if (-not $ConfigPath) { $ConfigPath = "$tools\..\RacingDSX_exe\RacingDSX.json" }
$gamePort = 5310; $dsxPort = 6970
if (Get-NetUDPEndpoint -LocalPort $gamePort, $dsxPort -ErrorAction SilentlyContinue) {
    throw "UDP $gamePort or $dsxPort is busy (another check still running?)."
}

# Wall clock in seconds. The listener stamps packets with the same clock, so scenario
# boundaries recorded here line up with what it captured.
function Now { [DateTime]::UtcNow.Ticks / 1e7 }

$box = Join-Path $env:TEMP ("racingdsx_brake_probe_" + (Get-Date -Format "HHmmss"))
New-Item -ItemType Directory -Force -Path $box | Out-Null
Copy-Item $ExePath $box
Copy-Item (Join-Path (Split-Path $ExePath -Parent) "RacingDSX.dll.config") $box -ErrorAction SilentlyContinue
((Get-Content $ConfigPath -Raw) `
    -replace '"DisableAppCheck":false', '"DisableAppCheck":true' `
    -replace '"gameUDPPort":\d+', "`"gameUDPPort`":$gamePort" `
    -replace '"DSXPort":\d+', "`"DSXPort`":$dsxPort") |
    Out-File "$box\RacingDSX.json" -Encoding utf8 -NoNewline

# l = number of locked wheels (they stop turning while the car moves); s = combined tyre slip.
# The gravel row uses 3.15, the slip a fully locked wheel reports on gravel in real recordings.
$steady = @(
    @{ n = 'light brake, rolling';          b = 60;  s = 0.02; l = 0 },
    @{ n = 'medium brake, rolling';         b = 150; s = 0.02; l = 0 },
    @{ n = 'hard brake, rolling';           b = 230; s = 0.02; l = 0 },
    @{ n = 'hard brake, slipping, rolls';   b = 230; s = 1.5;  l = 0 },
    @{ n = 'hard brake, 1 wheel locked';    b = 230; s = 1.0;  l = 1 },
    @{ n = 'hard brake, 2 wheels locked';   b = 230; s = 2.0;  l = 2 },
    @{ n = 'gravel full lock (slip 3.15)';  b = 255; s = 3.15; l = 4 },
    @{ n = 'asphalt full lock (slip 5.6)';  b = 255; s = 5.6;  l = 4 }
)
$holdSeconds  = 3
$spikeSeconds = 6

$capture = "$box\capture.json"
$listenSeconds = [int]($steady.Count * ($holdSeconds + 1.5) + $spikeSeconds + 10)
$listener = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$tools\fake_dsx.ps1",
    "-Seconds", $listenSeconds, "-Port", $dsxPort, "-OutFile", $capture)
Start-Sleep -Seconds 2
$app = Start-Process "$box\RacingDSX.exe" -WorkingDirectory $box -PassThru
Start-Sleep -Seconds 2

$marks = @()
foreach ($c in $steady) {
    $start = Now
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\fake_forza.ps1" -Port $gamePort `
        -Seconds $holdSeconds -RateHz 140 -Brake $c.b -Slip $c.s -LockWheels $c.l | Out-Null
    $marks += [pscustomobject]@{ Name = $c.n; Start = $start; End = (Now) }
}

$spikeStart = Now
$spikeOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\fake_forza.ps1" -Port $gamePort `
    -Seconds $spikeSeconds -RateHz 140 -Brake 230 -Slip 1.0 -SpikeSlip 6.0 -SpikeEveryMs 300 -SpikeFrames 2
$spikeEnd = Now
$spikesSent = ($spikeOut | Select-String 'spikes=(\d+)').Matches[0].Groups[1].Value

Start-Sleep -Seconds 1
Stop-Process -Id $app.Id -Force   # only our sandboxed copy
# The listener writes its file only when its time is up; wait for it rather than guess.
$listener.WaitForExit()

# Windows PowerShell 5.1 emits a JSON array as ONE pipeline object, so @(...) around the
# pipeline would produce a 1-element array holding the real one. Assign, then unroll.
$parsed = Get-Content $capture -Raw | ConvertFrom-Json
$rows = @($parsed | ForEach-Object { $_ })
function Get-Left($row) {
    ($row.Json | ConvertFrom-Json).instructions |
        Where-Object { $_.type -eq 1 -and $_.parameters[1] -eq 1 } | Select-Object -First 1
}

Write-Output "exe: $ExePath   ($($rows.Count) packets captured)"
Write-Output ""
Write-Output "Steady inputs (left trigger over the second half of each $holdSeconds s hold):"
foreach ($m in $marks) {
    $from = $m.Start + ($m.End - $m.Start) / 2
    $seen = $rows | Where-Object { $_.W -ge $from -and $_.W -le $m.End } |
        ForEach-Object { $l = Get-Left $_; if ($l) { '[' + ($l.parameters -join ',') + ']' } } |
        Select-Object -Unique
    "  {0,-30} -> {1}" -f $m.Name, ($seen -join '  ')
}

# Count vibration episodes: runs of consecutive packets whose left trigger is mode 12.
$episodes = 0; $inVib = $false
$rows | Where-Object { $_.W -ge $spikeStart -and $_.W -le ($spikeEnd + 0.3) } | ForEach-Object {
    $l = Get-Left $_
    if (-not $l) { return }
    $vib = ($l.parameters[2] -eq 12)
    if ($vib -and -not $inVib) { $episodes++ }
    $inVib = $vib
}
Write-Output ""
Write-Output "Brief lock-ups (all wheels locked for 2 packets = ~14 ms, every 300 ms):"
Write-Output "  lock-ups sent by game: $spikesSent   vibration bursts reaching DSX: $episodes"
