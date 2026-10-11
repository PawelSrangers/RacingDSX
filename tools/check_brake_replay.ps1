# Replays a real recording through a RacingDSX exe and reports, per braking event, how often
# the wheels were locked and what the brake (left) trigger actually received from the exe.
#
#   powershell -ExecutionPolicy Bypass -File tools\check_brake_replay.ps1 recordings\gravel_rally_20261011_200137.fzrec
#   ... -ExePath RacingDSX_exe\backup_original\RacingDSX.exe
#
# "lock%" = share of event frames where at least one wheel turns at < 35% of the car's speed
# (wheel radius 0.32 m, measured from the recordings). Trigger shares are the share of the
# event's time the trigger spent in each state:
# vib = vibration (CustomTriggerValue), res = resistance > 0, ZERO = resistance 0, normal = released
# The sandboxed exe is pointed at its own ports (game 5310, DSX 6970), so this runs fine with
# the real DSX, RacingDSX and even the game open. Takes as long as the recording.

param(
    [Parameter(Mandatory = $true)][string]$Recording,
    [string]$ExePath = ""
)

$ErrorActionPreference = "Stop"
$tools = Split-Path $MyInvocation.MyCommand.Path -Parent
$root = Split-Path $tools -Parent
if (-not $ExePath) { $ExePath = "$root\RacingDSX_exe\RacingDSX.exe" }
$Recording = (Resolve-Path $Recording).Path
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function N($s) { [double]::Parse($s, $inv) }

$gamePort = 5310; $dsxPort = 6970
if (Get-NetUDPEndpoint -LocalPort $gamePort,$dsxPort -ErrorAction SilentlyContinue) {
    throw "UDP $gamePort or $dsxPort is busy (another check still running?)."
}

$csv = [System.IO.Path]::ChangeExtension($Recording, ".csv")
if (-not (Test-Path $csv)) { & powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\decode_recording.ps1" $Recording | Out-Null }
$rows = Import-Csv $csv
$duration = (N $rows[-1].t)

$box = Join-Path $env:TEMP ("racingdsx_replay_" + (Get-Date -Format "HHmmss"))
New-Item -ItemType Directory -Force -Path $box | Out-Null
Copy-Item $ExePath $box
Copy-Item (Join-Path (Split-Path $ExePath -Parent) "RacingDSX.dll.config") $box -ErrorAction SilentlyContinue
((Get-Content "$root\RacingDSX_exe\RacingDSX.json" -Raw) `
    -replace '"DisableAppCheck":false', '"DisableAppCheck":true' `
    -replace '"gameUDPPort":\d+', "`"gameUDPPort`":$gamePort" `
    -replace '"DSXPort":\d+', "`"DSXPort`":$dsxPort") |
    Out-File "$box\RacingDSX.json" -Encoding utf8 -NoNewline

$capture = "$box\capture.json"
$listener = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$tools\fake_dsx.ps1",
    "-Seconds", [int]($duration + 12), "-Port", $dsxPort, "-OutFile", $capture)
Start-Sleep -Seconds 2
$app = Start-Process "$box\RacingDSX.exe" -WorkingDirectory $box -PassThru
Start-Sleep -Seconds 2

$replayOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\replay_recording.ps1" $Recording -Port $gamePort
$w0 = N (($replayOut | Select-String '^W0=(.+)$').Matches[0].Groups[1].Value)

Start-Sleep -Seconds 1
# Only our sandboxed copy; the user's own RacingDSX may be running.
Stop-Process -Id $app.Id -Force
$listener.WaitForExit()
$parsed = Get-Content $capture -Raw | ConvertFrom-Json
$dsx = @($parsed | ForEach-Object { $_ })

# Left trigger state per DSX packet, with time on the recording's clock.
$left = foreach ($p in $dsx) {
    $l = ($p.Json | ConvertFrom-Json).instructions | Where-Object { $_.type -eq 1 -and $_.parameters[1] -eq 1 } | Select-Object -First 1
    if (-not $l) { continue }
    $mode = [int]$l.parameters[2]
    $kind = if ($mode -eq 12) { 'vib' } elseif ($mode -eq 13 -and [double]$l.parameters[4] -gt 0) { 'res' } elseif ($mode -eq 13) { 'ZERO' } else { 'normal' }
    [pscustomobject]@{ T = $p.W - $w0; Kind = $kind }
}

# Braking events, same rule as analyze_braking.ps1.
$events = @(); $cur = $null
foreach ($r in $rows) {
    if ([int]$r.Brake -gt 30 -and (N $r.Speed) -gt 3) {
        if (-not $cur) { $cur = New-Object System.Collections.Generic.List[object] }
        $cur.Add($r)
    } elseif ($cur) { if ($cur.Count -ge 20) { $events += , $cur }; $cur = $null }
}
if ($cur -and $cur.Count -ge 20) { $events += , $cur }

Write-Output ("exe: {0}" -f $ExePath)
Write-Output ("recording: {0}  ({1} packets, {2:N0} s; {3} DSX packets captured)" -f (Split-Path $Recording -Leaf), $rows.Count, $duration, $left.Count)
$fmt = "{0,3} {1,7} {2,6} {3,6} {4,6}   {5}"
Write-Output ($fmt -f '#', 't(s)', 'km/h', 'brake', 'lock%', 'brake trigger got')
$i = 0; $tot = @{}; $lockTot = @{}
foreach ($e in $events) {
    $i++
    $locked = 0
    foreach ($r in $e) {
        $v = N $r.Speed
        foreach ($w in 'FL', 'FR', 'RL', 'RR') {
            if ($v -gt 3 -and [Math]::Abs((N $r."WheelRotSpeed$w")) * 0.32 / $v -lt 0.35) { $locked++; break }
        }
    }
    # Time-weighted: the trigger keeps its last state until the next packet, and unchanged
    # states are not resent (dedupe), so counting packets would under-weight steady vibration.
    $from = (N $e[0].t) + 0.05; $to = (N $e[-1].t)
    $got = @{}
    $k = 0
    for ($t = $from; $t -le $to; $t += 0.01) {
        while ($k + 1 -lt $left.Count -and $left[$k + 1].T -le $t) { $k++ }
        $state = $left[$k]
        if ($state.T -gt $t) { continue }
        $got[$state.Kind] = 1 + [int]$got[$state.Kind]
        $tot[$state.Kind] = 1 + [int]$tot[$state.Kind]
        if ($locked / $e.Count -ge 0.5) { $lockTot[$state.Kind] = 1 + [int]$lockTot[$state.Kind] }
    }
    $n = ($got.Values | Measure-Object -Sum).Sum
    $share = ($got.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "{0} {1:P0}" -f $_.Key, ($_.Value / [Math]::Max($n, 1)) }) -join ', '
    $maxBrake = ($e | ForEach-Object { [int]$_.Brake } | Measure-Object -Maximum).Maximum
    Write-Output ($fmt -f $i, (N $e[0].t).ToString('0.0'), ((N $e[0].Speed) * 3.6).ToString('0'), $maxBrake, ('{0:P0}' -f ($locked / $e.Count)), $share)
}
function Fmt($h) { $s = ($h.Values | Measure-Object -Sum).Sum; ($h.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "{0} {1:P0}" -f $_.Key, ($_.Value / [Math]::Max($s, 1)) }) -join ', ' }
Write-Output ""
Write-Output ("All braking:                 " + (Fmt $tot))
Write-Output ("Events with lock >= 50%:     " + (Fmt $lockTot))
