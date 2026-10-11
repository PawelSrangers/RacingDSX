# Finds braking events in a decoded recording (CSV from decode_recording.ps1) and shows, per
# event, what the tyres were doing and what the brake trigger would get from Parser's
# GetInRaceLeftTriggerInstruction with the user's current brake settings.
#
#   powershell -ExecutionPolicy Bypass -File tools\analyze_braking.ps1 recordings\gravel_rally_*.csv
#
# "Locked" = wheel turning slower than 2 rad/s while the car does more than 5 m/s.
# The trigger simulation ignores EWMA smoothing; it shows which branch the code takes.

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$ConfigPath = "",
    [int]$BrakeOn = 30          # brake byte above which a frame counts as braking
)

$ErrorActionPreference = "Stop"
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function N($s) { [double]::Parse($s, $inv) }

# Resolved here rather than as a param default: $PSScriptRoot is not reliably set there in
# Windows PowerShell 5.1.
if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "..\RacingDSX_exe\RacingDSX.json"
}
$bs = (Get-Content $ConfigPath -Raw | ConvertFrom-Json).Profiles.Forza.brakeSettings
function Map($x, $inMin, $inMax, $outMin, $outMax) {
    if ($inMax -eq $inMin) { return $outMin }
    if ($x -gt $inMax) { $x = $inMax } elseif ($x -lt $inMin) { $x = $inMin }
    ($x - $inMin) * ($outMax - $outMin) / ($inMax - $inMin) + $outMin
}
# Mirrors Parser.GetInRaceLeftTriggerInstruction (without EWMA). Returns a short label.
function Trigger($brake, $slip) {
    if ($bs.TriggerMode -eq 0) { return 'off' }
    $losing = ($slip -gt $bs.GripLossValue) -and ($brake -gt 100)
    if ($losing -and $bs.TriggerMode -eq 2) {
        $freq = [Math]::Floor((Map $slip $bs.GripLossValue 5 0 $bs.MaxVibration))
        if ($freq -le $bs.MinVibration) { return 'ZERO' }
        return "vib$freq"
    }
    $r = [Math]::Floor((Map $brake 0 255 $bs.MinResistance $bs.MaxResistance))
    return "res$r"
}

$rows = Import-Csv $Path
$name = Split-Path $Path -Leaf
$dur = (N $rows[-1].t) - (N $rows[0].t)

$puddle = ($rows | ForEach-Object { [Math]::Max([Math]::Max((N $_.PuddleFL), (N $_.PuddleFR)), [Math]::Max((N $_.PuddleRL), (N $_.PuddleRR))) } | Measure-Object -Maximum -Average)
$rumble = ($rows | Where-Object { (N $_.Speed) -gt 5 } | ForEach-Object { ((N $_.SurfaceRumbleFL) + (N $_.SurfaceRumbleFR) + (N $_.SurfaceRumbleRL) + (N $_.SurfaceRumbleRR)) / 4 } | Measure-Object -Average)

Write-Output "=== $name ==="
Write-Output ("{0} packets, {1:N0} s, {2:N0} packets/s, car ordinal {3}, class {4}, PI {5}, drivetrain {6}" -f $rows.Count, $dur, ($rows.Count / [Math]::Max($dur, 1)), $rows[0].CarOrdinal, $rows[0].CarClass, $rows[0].CarPI, $rows[0].Drivetrain)
Write-Output ("puddle depth: max {0:N2}, avg {1:N3}    surface rumble while moving: avg {2:N3}" -f $puddle.Maximum, $puddle.Average, $rumble.Average)
Write-Output ("brake settings: GripLoss {0}, MinVib {1}, MaxVib {2}, Resistance {3}..{4}" -f $bs.GripLossValue, $bs.MinVibration, $bs.MaxVibration, $bs.MinResistance, $bs.MaxResistance)
Write-Output ""

# Group consecutive braking frames into events.
$events = @(); $cur = $null
foreach ($r in $rows) {
    $braking = ([int]$r.Brake -gt $BrakeOn) -and ((N $r.Speed) -gt 3)
    if ($braking) {
        if (-not $cur) { $cur = New-Object System.Collections.Generic.List[object] }
        $cur.Add($r)
    } elseif ($cur) {
        if ($cur.Count -ge 20) { $events += , $cur }
        $cur = $null
    }
}
if ($cur -and $cur.Count -ge 20) { $events += , $cur }

$fmt = "{0,3} {1,7} {2,5} {3,8} {4,9} {5,6} {6,9} {7,9} {8,11} {9,-34}"
Write-Output ($fmt -f '#', 't(s)', 'dur', 'km/h', 'brakeMax', 'lock%', 'slip med', 'slip max', 'slipRatio', 'trigger gets (share of frames)')
$i = 0
$tot = @{}
foreach ($e in $events) {
    $i++
    $lockFrames = 0; $slips = @(); $ratios = @(); $labels = @{}
    foreach ($r in $e) {
        $spd = N $r.Speed
        $locked = 0
        foreach ($w in 'FL', 'FR', 'RL', 'RR') { if ([Math]::Abs((N $r."WheelRotSpeed$w")) -lt 2 -and $spd -gt 5) { $locked++ } }
        if ($locked -ge 2) { $lockFrames++ }
        $s = ([Math]::Abs((N $r.CombinedSlipFL)) + [Math]::Abs((N $r.CombinedSlipFR)) + [Math]::Abs((N $r.CombinedSlipRL)) + [Math]::Abs((N $r.CombinedSlipRR))) / 4
        $slips += $s
        $ratios += ((N $r.SlipRatioFL) + (N $r.SlipRatioFR) + (N $r.SlipRatioRL) + (N $r.SlipRatioRR)) / 4
        $lab = Trigger ([int]$r.Brake) $s
        $kind = if ($lab -like 'vib*') { 'vib' } elseif ($lab -like 'res*' -and $lab -ne 'res0') { 'resistance' } elseif ($lab -eq 'res0') { 'res0' } else { $lab }
        $labels[$kind] = 1 + [int]$labels[$kind]
        $tot[$kind] = 1 + [int]$tot[$kind]
    }
    $sorted = $slips | Sort-Object
    $med = $sorted[[int]($sorted.Count / 2)]
    $share = ($labels.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "{0} {1:P0}" -f $_.Key, ($_.Value / $e.Count) }) -join ', '
    $maxBrake = ($e | ForEach-Object { [int]$_.Brake } | Measure-Object -Maximum).Maximum
    Write-Output ($fmt -f $i, ((N $e[0].t).ToString('0.0')), ((N $e[-1].t) - (N $e[0].t)).ToString('0.0'),
        ((N $e[0].Speed) * 3.6).ToString('0'), $maxBrake, ('{0:P0}' -f ($lockFrames / $e.Count)),
        $med.ToString('0.00'), ($sorted[-1]).ToString('0.00'), (($ratios | Measure-Object -Minimum).Minimum).ToString('0.00'), $share)
}
Write-Output ""
$all = ($tot.Values | Measure-Object -Sum).Sum
Write-Output ("All braking frames: " + (($tot.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "{0} {1:P0}" -f $_.Key, ($_.Value / [Math]::Max($all, 1)) }) -join ', '))
