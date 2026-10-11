# Screenshots the running RacingDSX window, optionally clicking something first.
# Useful because UI.Designer.cs cannot be opened without Visual Studio, so the only
# way to check a layout or theme change is to look at the built app.
#
#   Start RacingDSX, then:
#   powershell -ExecutionPolicy Bypass -File tools\screenshot_ui.ps1 -OutFile misc.png
#   powershell -ExecutionPolicy Bypass -File tools\screenshot_ui.ps1 -RelX 340 -RelY 66 -OutFile brake.png
#
# Coordinates are relative to the window's top-left. Tab strip sits at y=66; at the
# default 1500x880 size the tabs are near x=240 (Misc), 340 (Brake), 470 (Throttle),
# 578 (Output).
#
# SetProcessDPIAware matters: without it, a scaled display makes GetWindowRect return
# virtualised coordinates while CopyFromScreen captures physical pixels, so the capture
# is offset and every click lands somewhere else than intended.

param(
    [int]$RelX = 0,
    [int]$RelY = 0,
    [string]$OutFile = "ui.png",
    [int]$Width  = 1500,
    [int]$Height = 880
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class UiShot {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool r);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@

[void][UiShot]::SetProcessDPIAware()

$p = Get-Process RacingDSX -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { throw "RacingDSX is not running (or has no window yet)." }
$h = $p.MainWindowHandle

[void][UiShot]::ShowWindow($h, 9)   # SW_RESTORE
[void][UiShot]::MoveWindow($h, 60, 60, $Width, $Height, $true)
[void][UiShot]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 800

$r = New-Object UiShot+RECT
[void][UiShot]::GetWindowRect($h, [ref]$r)

if ($RelX -gt 0 -or $RelY -gt 0) {
    [void][UiShot]::SetCursorPos(($r.L + $RelX), ($r.T + $RelY))
    Start-Sleep -Milliseconds 250
    [UiShot]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
    [UiShot]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)   # LEFTUP
    Start-Sleep -Milliseconds 800
    [void][UiShot]::GetWindowRect($h, [ref]$r)
}

$w = $r.R - $r.L; $t = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $t)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

Write-Output "saved $OutFile ($w x $t)"
