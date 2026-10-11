# Decodes a .fzrec file from record_forza.ps1 into CSV, one row per packet, every field of
# the Forza Horizon "Car Dash" layout (324 bytes, dash section shifted by 12 bytes).
#
#   powershell -ExecutionPolicy Bypass -File tools\decode_recording.ps1 recordings\gravel_rally_*.fzrec
#
# Writes <file>.csv next to the recording. Floats use '.' as the decimal separator.

param([Parameter(Mandatory = $true)][string]$Path)

$ErrorActionPreference = "Stop"
$file = (Resolve-Path $Path).Path
$reader = New-Object System.IO.BinaryReader([System.IO.File]::OpenRead($file))
$magic = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(6))
if ($magic -ne "FZREC1") { throw "Not a .fzrec file (magic '$magic')" }

$inv = [System.Globalization.CultureInfo]::InvariantCulture
function F([byte[]]$b, [int]$o) { [BitConverter]::ToSingle($b, $o).ToString("0.#####", $inv) }
function I32([byte[]]$b, [int]$o) { [BitConverter]::ToInt32($b, $o) }
function U8([byte[]]$b, [int]$o) { $b[$o] }
# PowerShell's [sbyte] cast is range-checked (255 throws), so do the two's complement by hand.
function S8([byte[]]$b, [int]$o) { $x = [int]$b[$o]; if ($x -gt 127) { $x - 256 } else { $x } }

$wheels = 'FL', 'FR', 'RL', 'RR'
$cols = @('t', 'len', 'IsRaceOn', 'TimestampMs', 'EngineMaxRpm', 'EngineIdleRpm', 'Rpm',
    'AccelX', 'AccelY', 'AccelZ', 'VelX', 'VelY', 'VelZ', 'AngVelX', 'AngVelY', 'AngVelZ',
    'Yaw', 'Pitch', 'Roll')
foreach ($g in 'SuspNorm', 'SlipRatio', 'WheelRotSpeed', 'RumbleStrip', 'Puddle',
               'SurfaceRumble', 'SlipAngle', 'CombinedSlip', 'SuspMeters') {
    foreach ($w in $wheels) { $cols += "$g$w" }
}
$cols += 'CarOrdinal', 'CarClass', 'CarPI', 'Drivetrain', 'Cylinders',
    'CarGroup', 'SmashableVelDiff', 'SmashableMass',
    'PosX', 'PosY', 'PosZ', 'Speed', 'Power', 'Torque',
    'TireTempFL', 'TireTempFR', 'TireTempRL', 'TireTempRR', 'Boost', 'Fuel', 'Distance',
    'BestLap', 'LastLap', 'CurrentLap', 'RaceTime', 'Lap', 'RacePos',
    'Accel', 'Brake', 'Clutch', 'Handbrake', 'Gear', 'Steer', 'DrivingLine', 'AiBrakeDiff'

$out = [System.IO.Path]::ChangeExtension($file, ".csv")
$sw = New-Object System.IO.StreamWriter($out, $false, (New-Object System.Text.UTF8Encoding($false)))
$sw.WriteLine(($cols -join ','))

$t0 = $null; $n = 0; $skipped = 0
try {
    while ($reader.BaseStream.Position -lt $reader.BaseStream.Length) {
        $t = $reader.ReadDouble()
        $len = $reader.ReadInt32()
        $b = $reader.ReadBytes($len)
        if ($b.Length -ne $len) { break }   # truncated tail (window closed mid-write)
        if ($null -eq $t0) { $t0 = $t }
        if ($len -ne 324) { $skipped++; continue }

        $v = New-Object System.Collections.Generic.List[string]
        $v.Add(($t - $t0).ToString("0.000", $inv)); $v.Add($len)
        # Spec says int32 1/0; normalise so a float 1.0 (as fake_forza writes it) reads as 1 too.
        $v.Add($(if ((I32 $b 0) -ne 0) { 1 } else { 0 }))
        $v.Add([BitConverter]::ToUInt32($b, 4))
        for ($o = 8; $o -le 64; $o += 4) { $v.Add((F $b $o)) }          # rpm .. roll
        for ($o = 68; $o -le 208; $o += 4) { $v.Add((F $b $o)) }        # 9 per-wheel groups
        foreach ($o in 212, 216, 220, 224, 228) { $v.Add((I32 $b $o)) }
        $v.Add((I32 $b 232)); $v.Add((F $b 236)); $v.Add((F $b 240))    # FH extras
        for ($o = 244; $o -le 308; $o += 4) { $v.Add((F $b $o)) }       # pos .. race time
        $v.Add([BitConverter]::ToUInt16($b, 312)); $v.Add((U8 $b 314))
        foreach ($o in 315, 316, 317, 318, 319) { $v.Add((U8 $b $o)) }
        $v.Add((S8 $b 320)); $v.Add((S8 $b 321)); $v.Add((S8 $b 322))
        $sw.WriteLine(($v -join ','))
        $n++
    }
}
finally {
    $sw.Dispose(); $reader.Dispose()
}

Write-Output "$n packets -> $out"
if ($skipped) { Write-Output "skipped $skipped packets that were not 324 bytes" }
