# Records raw Forza "Data Out" telemetry to a file, exactly as the game sends it, so it can
# be decoded and replayed through RacingDSX later.
#
#   powershell -ExecutionPolicy Bypass -File tools\record_forza.ps1 -Name gravel_rally
#
# RacingDSX must be CLOSED while recording: the game can only send to one port, and both
# programs want 5300. DSX can stay open. Press Ctrl+C to finish; the file is flushed every
# second, so even closing the window loses at most the last second.
#
# File format (.fzrec): ASCII "FZREC1", then per packet:
#   double   arrival time, Unix seconds (little-endian)
#   int32    packet length
#   byte[]   packet, untouched

param(
    [string]$Name = "session",
    [int]$Port = 5300,
    [string]$OutDir = "$PSScriptRoot\..\recordings",
    # Stop on its own after this many seconds (0 = run until Ctrl+C). Used for testing.
    [int]$Seconds = 0
)

$ErrorActionPreference = "Stop"

$busy = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue
if ($busy) {
    $who = (Get-Process -Id $busy[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
    Write-Host "UDP $Port is already taken by '$who'. Close it (RacingDSX?) and run again." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$safeName = ($Name -replace '[^\w\-]', '_')
$path = Join-Path (Resolve-Path $OutDir) ("{0}_{1}.fzrec" -f $safeName, (Get-Date -Format "yyyyMMdd_HHmmss"))

$udp = New-Object System.Net.Sockets.UdpClient($Port)
$udp.Client.ReceiveTimeout = 1000
$ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

$stream = [System.IO.File]::Create($path)
$writer = New-Object System.IO.BinaryWriter($stream)
$writer.Write([System.Text.Encoding]::ASCII.GetBytes("FZREC1"))

$count = 0
$firstAt = $null
$lastFlush = [DateTime]::UtcNow
$lastStatus = [DateTime]::MinValue
$last = $null

Write-Host "Recording to $path"
Write-Host "Waiting for telemetry on UDP $Port... (Data Out: 127.0.0.1, port $Port). Ctrl+C to stop."
Write-Host ""

$startedAt = [DateTime]::UtcNow
try {
    while ($Seconds -le 0 -or ([DateTime]::UtcNow - $startedAt).TotalSeconds -lt $Seconds) {
        try {
            $bytes = $udp.Receive([ref]$ep)
            $now = [DateTime]::UtcNow
            $writer.Write([double]($now.Ticks / 1e7))
            $writer.Write([int]$bytes.Length)
            $writer.Write($bytes)
            $count++
            if (-not $firstAt) { $firstAt = $now }
            $last = $bytes
        } catch [System.Net.Sockets.SocketException] {
            # 1 s without packets: menu / pause, or not driving yet. Keep waiting.
        }

        $now = [DateTime]::UtcNow
        if (($now - $lastFlush).TotalSeconds -ge 1) {
            $writer.Flush(); $stream.Flush()
            $lastFlush = $now
        }

        if (($now - $lastStatus).TotalMilliseconds -ge 250) {
            $lastStatus = $now
            $secs = if ($firstAt) { [int]($now - $firstAt).TotalSeconds } else { 0 }
            $line = "  packets: {0,7}   time: {1,4}s" -f $count, $secs
            if ($last -and $last.Length -eq 324) {
                $speed = [BitConverter]::ToSingle($last, 256) * 3.6
                $brake = $last[316]
                $slip = 0.0
                foreach ($off in 180, 184, 188, 192) { $slip += [Math]::Abs([BitConverter]::ToSingle($last, $off)) }
                $line += "   speed: {0,5:N0} km/h   brake: {1,3}   tyre slip: {2,5:N2}" -f $speed, $brake, ($slip / 4)
            } elseif ($last) {
                $line += "   (packet size $($last.Length) bytes)"
            }
            Write-Host -NoNewline ("`r" + $line.PadRight(100))
        }
    }
}
finally {
    $writer.Flush()
    $writer.Dispose()
    $udp.Close()
    Write-Host ""
    Write-Host ""
    Write-Host "Saved $count packets to:"
    Write-Host "  $path"
}
