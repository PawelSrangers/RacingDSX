# Shows what the LEFT (brake) trigger receives for fixed brake / tyre-slip inputs, and how
# many brief lock-up spikes make it through to DSX as vibration.
#
#   powershell -ExecutionPolicy Bypass -File tools\probe_brake.ps1
#   powershell -ExecutionPolicy Bypass -File tools\probe_brake.ps1 -ExePath RacingDSX_exe\backup_original\RacingDSX.exe
#
# Left-trigger params are [controller, 1=Left, mode, ...]:
#   mode 13 = Resistance, last number is force (0 = nothing)
#   mode 12 = CustomTriggerValue, next 9 = VibrateResistance, then frequency, stiffness
# Needs UDP 5300 and 6969 free (close real DSX and RacingDSX first). Takes about a minute.

param(
    [string]$ExePath = "$PSScriptRoot\..\RacingDSX_exe\RacingDSX.exe",
    [string]$ConfigPath = "$PSScriptRoot\..\RacingDSX_exe\RacingDSX.json"
)

$ErrorActionPreference = "Stop"
if (Get-NetUDPEndpoint -LocalPort 5300,6969 -ErrorAction SilentlyContinue) {
    throw "UDP 5300 or 6969 is busy; close DSX / RacingDSX first."
}

# Wall clock in seconds. The listener stamps packets with the same clock, so scenario
# boundaries recorded here line up with what it captured.
function Now { [DateTime]::UtcNow.Ticks / 1e7 }

$box = Join-Path $env:TEMP "racingdsx_brake_probe"
Remove-Item $box -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $box | Out-Null
Copy-Item $ExePath $box
Copy-Item (Join-Path (Split-Path $ExePath -Parent) "RacingDSX.dll.config") $box -ErrorAction SilentlyContinue
((Get-Content $ConfigPath -Raw) -replace '"DisableAppCheck":false', '"DisableAppCheck":true') |
    Out-File "$box\RacingDSX.json" -Encoding utf8 -NoNewline

$steady = @(
    @{ n = 'light brake, grip';         b = 60;  s = 0.02 },
    @{ n = 'medium brake, grip';        b = 150; s = 0.02 },
    @{ n = 'hard brake, grip (ABS)';    b = 230; s = 0.02 },
    @{ n = 'medium brake, slight slip'; b = 150; s = 0.3  },
    @{ n = 'hard brake, slip 1.5';      b = 230; s = 1.5  },
    @{ n = 'full brake, slip 3.0';      b = 255; s = 3.0  },
    @{ n = 'full brake, slip 4.5';      b = 255; s = 4.5  },
    @{ n = 'full brake, slip 8.0';      b = 255; s = 8.0  }
)
$holdSeconds  = 3
$spikeSeconds = 6

$capture = "$box\capture.json"
$listenSeconds = [int]($steady.Count * ($holdSeconds + 1.5) + $spikeSeconds + 10)
$listener = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$PSScriptRoot\fake_dsx.ps1",
    "-Seconds", $listenSeconds, "-OutFile", $capture)
Start-Sleep -Seconds 2
Start-Process "$box\RacingDSX.exe" -WorkingDirectory $box
Start-Sleep -Seconds 2

$marks = @()
foreach ($c in $steady) {
    $start = Now
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\fake_forza.ps1" `
        -Seconds $holdSeconds -RateHz 140 -Brake $c.b -Slip $c.s | Out-Null
    $marks += [pscustomobject]@{ Name = $c.n; Start = $start; End = (Now) }
}

$spikeStart = Now
$spikeOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\fake_forza.ps1" `
    -Seconds $spikeSeconds -RateHz 140 -Brake 230 -Slip 1.0 -SpikeSlip 6.0 -SpikeEveryMs 300 -SpikeFrames 2
$spikeEnd = Now
$spikesSent = ($spikeOut | Select-String 'spikes=(\d+)').Matches[0].Groups[1].Value

Start-Sleep -Seconds 1
Get-Process RacingDSX -ErrorAction SilentlyContinue | Stop-Process -Force
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
    "  {0,-28} -> {1}" -f $m.Name, ($seen -join '  ')
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
Write-Output "Brief lock-ups (2 packets = ~14 ms at slip 6.0 over a slip 1.0 base, every 300 ms):"
Write-Output "  spikes sent by game: $spikesSent   vibration bursts reaching DSX: $episodes"
