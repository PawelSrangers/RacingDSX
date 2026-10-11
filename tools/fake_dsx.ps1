# Stands in for DSX: listens on UDP 6969 and records every instruction packet
# RacingDSX sends, with arrival timestamps.
#
# The number that matters is the steady-state packet rate. Before the FH6 fix a
# 140/s telemetry stream produced ~419 packets/s here; it should now sit at or
# just under Config.DSXUpdateRateHz (default 30).
#
#   powershell -ExecutionPolicy Bypass -File tools\fake_dsx.ps1 -Seconds 16 -OutFile capture.json
#
# Run this BEFORE starting RacingDSX, or it will fail to bind the port.

param(
    [int]$Seconds = 16,
    [int]$Port    = 6969,
    [string]$OutFile
)

$udp = New-Object System.Net.Sockets.UdpClient($Port)
$udp.Client.ReceiveTimeout = 400
$ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

$rows = New-Object System.Collections.Generic.List[object]
$sw = [System.Diagnostics.Stopwatch]::StartNew()

while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    try {
        $bytes = $udp.Receive([ref]$ep)
        $rows.Add([PSCustomObject]@{
            T    = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
            # Wall clock, so other processes can line their own events up with ours.
            W    = [Math]::Round([DateTime]::UtcNow.Ticks / 1e7, 3)
            Json = [System.Text.Encoding]::ASCII.GetString($bytes)
        })
    } catch [System.Net.Sockets.SocketException] {
        # receive timeout; keep waiting so we also capture the idle-reset packet
    }
}
$udp.Close()

# Ignore the ramp-up and tail so the rate reflects steady state.
$lo = 3.0
$hi = [Math]::Max($lo + 1, $Seconds - 3)
$window = $rows | Where-Object { $_.T -ge $lo -and $_.T -le $hi }
Write-Output ("total={0}  steady-state={1} packets/sec (t={2}..{3}s)" -f $rows.Count,
    [Math]::Round($window.Count / ($hi - $lo), 1), $lo, $hi)
Write-Output "--- last 3 packets ---"
$rows | Select-Object -Last 3 | ForEach-Object { "{0,7}s  {1}" -f $_.T, $_.Json }

if ($OutFile) {
    $rows | ConvertTo-Json -Depth 3 | Out-File -FilePath $OutFile -Encoding utf8
}
