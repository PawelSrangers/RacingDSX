# Replays a .fzrec recording to UDP 5300 with its original timing, as if the game were
# running. Prints "W0=<unix seconds>" when the first packet goes out, so a listener using
# the same wall clock can line its capture up with the recording's own timeline.
#
#   powershell -ExecutionPolicy Bypass -File tools\replay_recording.ps1 recordings\gravel_rally_*.fzrec

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$TargetHost = "127.0.0.1",
    [int]$Port = 5300
)

$ErrorActionPreference = "Stop"
$reader = New-Object System.IO.BinaryReader([System.IO.File]::OpenRead((Resolve-Path $Path).Path))
if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(6)) -ne "FZREC1") { throw "Not a .fzrec file" }

# Load everything first so disk reads can't disturb the timing.
$times = New-Object System.Collections.Generic.List[double]
$packets = New-Object System.Collections.Generic.List[byte[]]
while ($reader.BaseStream.Position -lt $reader.BaseStream.Length) {
    $t = $reader.ReadDouble(); $len = $reader.ReadInt32(); $b = $reader.ReadBytes($len)
    if ($b.Length -ne $len) { break }
    $times.Add($t); $packets.Add($b)
}
$reader.Dispose()

$udp = New-Object System.Net.Sockets.UdpClient
$udp.Connect($TargetHost, $Port)
$t0 = $times[0]
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$w0 = [DateTime]::UtcNow.Ticks / 1e7
Write-Output ("W0={0}" -f $w0.ToString([System.Globalization.CultureInfo]::InvariantCulture))

for ($i = 0; $i -lt $packets.Count; $i++) {
    $due = ($times[$i] - $t0) * 1000.0
    while ($true) {
        $left = $due - $sw.Elapsed.TotalMilliseconds
        if ($left -le 0) { break }
        if ($left -gt 3) { [System.Threading.Thread]::Sleep(1) }
    }
    [void]$udp.Send($packets[$i], $packets[$i].Length)
}
$udp.Close()
Write-Output ("replayed {0} packets over {1:N1} s" -f $packets.Count, $sw.Elapsed.TotalSeconds)
