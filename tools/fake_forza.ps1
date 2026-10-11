# Stands in for the game: emits Forza Horizon 4/5/6 "Car Dash" telemetry (324 bytes)
# on UDP 5300 at a configurable rate.
#
# FH6 sends at the game's frame rate (~130-240/s); FH4/FH5 send a fixed 60/s.
# Use -RateHz 140 to reproduce FH6 conditions, -RateHz 60 for FH5.
#
#   powershell -ExecutionPolicy Bypass -File tools\fake_forza.ps1 -Seconds 10 -RateHz 140

param(
    [int]$Seconds = 10,
    [int]$RateHz  = 140,
    [string]$TargetHost = "127.0.0.1",
    [int]$Port    = 5300,
    # Emit a stationary car with no throttle so IsRaceOn() decays to false.
    [switch]$Idle,
    # Pin inputs instead of sweeping them, to probe one brake/slip combination.
    # -1 keeps the default sine sweep.
    [int]$Brake = -1,
    [float]$Slip = -1,
    # Lock this many wheels (FL, FR, RL, RR order): they stop turning while the car moves.
    # The others roll at the car's speed. RacingDSX detects locks from this, not from slip.
    [int]$LockWheels = 0,
    # Brief lock-ups: every SpikeEveryMs, for SpikeFrames packets lock all four wheels and
    # hold slip at SpikeSlip.
    [float]$SpikeSlip = -1,
    [int]$SpikeEveryMs = 300,
    [int]$SpikeFrames = 2
)

$udp = New-Object System.Net.Sockets.UdpClient
$udp.Connect($TargetHost, $Port)

function Set-F32([byte[]]$buf, [int]$off, [float]$v) {
    [System.BitConverter]::GetBytes($v).CopyTo($buf, $off)
}

$intervalMs = 1000.0 / $RateHz
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$sent = 0
$next = 0.0
$nextSpikeMs = 500.0
$spikeLeft = 0
$spikesSent = 0
$inSpike = $false

while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    if ($sw.Elapsed.TotalMilliseconds -lt $next) { continue }
    $next = $sw.Elapsed.TotalMilliseconds + $intervalMs

    $t = $sw.Elapsed.TotalSeconds
    $buf = New-Object byte[] 324

    # --- sled section (offsets are absolute) ---
    Set-F32 $buf 0   1.0                                   # IsRaceOn
    Set-F32 $buf 8   8000.0                                # EngineMaxRpm
    Set-F32 $buf 12  800.0                                 # EngineIdleRpm
    if ($Idle) {
        Set-F32 $buf 16  800.0                             # CurrentEngineRpm, constant
    } else {
        Set-F32 $buf 16 ([float](4000 + 3000 * [Math]::Sin($t * 6)))
    }
    Set-F32 $buf 20  ([float](3 * [Math]::Sin($t * 3)))    # AccelerationX
    Set-F32 $buf 28  ([float](5 * [Math]::Cos($t * 3)))    # AccelerationZ
    Set-F32 $buf 180 ([float](0.9 + 0.5 * [Math]::Sin($t * 8)))  # TireCombinedSlip FL
    Set-F32 $buf 184 ([float](0.9 + 0.5 * [Math]::Sin($t * 8)))  # FR
    Set-F32 $buf 188 ([float](0.9 + 0.5 * [Math]::Cos($t * 8)))  # RL
    Set-F32 $buf 192 ([float](0.9 + 0.5 * [Math]::Cos($t * 8)))  # RR
    $slipNow = $Slip
    if ($SpikeSlip -ge 0) {
        if ($sw.Elapsed.TotalMilliseconds -ge $nextSpikeMs) {
            $spikeLeft = $SpikeFrames
            $nextSpikeMs = $sw.Elapsed.TotalMilliseconds + $SpikeEveryMs
            $spikesSent++
        }
        $inSpike = $spikeLeft -gt 0
        if ($inSpike) { $slipNow = $SpikeSlip; $spikeLeft-- }
    }
    if ($slipNow -ge 0) {
        foreach ($off in 180, 184, 188, 192) { Set-F32 $buf $off $slipNow }
    }

    # Wheels on the ground (normalized suspension travel; ~0 would mean airborne) and turning
    # at the car's speed for a 0.32 m wheel, except the locked ones.
    $speed = [float](40 + 20 * [Math]::Sin($t))
    $locked = if ($SpikeSlip -ge 0 -and $inSpike) { 4 } else { $LockWheels }
    for ($w = 0; $w -lt 4; $w++) {
        Set-F32 $buf (68 + 4 * $w) 0.4
        Set-F32 $buf (100 + 4 * $w) $(if ($w -lt $locked) { 0.0 } else { $speed / 0.32 })
    }
    $buf[216] = 4                                          # CarClass (S1)
    $buf[220] = 200                                        # CarPerformanceIndex

    # --- dash section: FMData.BufferOffset = 12 for the Horizon layout ---
    Set-F32 $buf 256 $speed                                # Speed  (244 + 12)
    if ($Idle) {
        Set-F32 $buf 260 0.0                               # Power  (248 + 12)
        $buf[315] = 0                                      # Accelerator (303 + 12)
        $buf[316] = 0                                      # Brake       (304 + 12)
    } else {
        Set-F32 $buf 260 150000.0
        $buf[315] = [byte](128 + 120 * [Math]::Sin($t * 4))
        $buf[316] = [byte](128 + 120 * [Math]::Cos($t * 4))
    }
    if ($Brake -ge 0) {
        $buf[316] = [byte]$Brake
    }

    [void]$udp.Send($buf, $buf.Length)
    $sent++
}
$udp.Close()

if ($SpikeSlip -ge 0) { Write-Output "spikes=$spikesSent" }
Write-Output ("sent={0} elapsed={1}s rate={2}/s" -f $sent,
    [Math]::Round($sw.Elapsed.TotalSeconds, 2),
    [Math]::Round($sent / $sw.Elapsed.TotalSeconds, 1))
