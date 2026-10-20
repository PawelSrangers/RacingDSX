# RacingDSX for Forza Horizon 6

DualSense adaptive triggers and light bar for Forza, driven by the game's telemetry through
[DSX](https://store.steampowered.com/app/1812620/DSX/). This is a patched fork of
[cosmii02/RacingDSX](https://github.com/cosmii02/RacingDSX) 0.6.7, fixed for **Forza Horizon 6**.
FH4, FH5, FM7, FM8 / Motorsport (2023) and DiRT Rally 1/2 keep working as before.

```
Forza  --UDP 5300 (telemetry)-->  RacingDSX  --UDP 6969-->  DSX  -->  DualSense
```

RacingDSX only sets trigger resistance / vibration and the light bar colour. Sticks and buttons
reach the game through DSX's virtual controller, not through RacingDSX.

## What this fork changes

**Forza Horizon 6 support**

- **No more "sticking" steering.** FH6 sends telemetry at the game's frame rate (130–240/s)
  instead of a fixed 60 Hz. Upstream forwarded three messages per packet, ~420/s, which stalled
  DSX until its virtual pad froze on its last state: steering or throttle stuck with the stick
  already released. RacingDSX now sends at most `DSXUpdateRateHz` (default 30) combined
  messages per second and skips repeats.
- **Short lock-ups are not lost.** A one-frame wheel lock or wheelspin between two sends is held
  and delivered in the next one.
- **Triggers are released in menus.** FH6 stops sending telemetry in menus, pause, replays and
  after a race. RacingDSX notices the silence (0.5 s) and releases the triggers instead of leaving
  them stiff.

**Brake trigger**

- **Wheel lock is detected from wheel speed against car speed, not from tyre slip.** Forza scales
  slip by surface grip, so a locked wheel reads ~5.6 on asphalt but ~3.15 on gravel, and upstream
  never vibrated on gravel. It dropped the brake resistance to zero instead. Measured on a real
  FH6 gravel recording: the trigger now vibrates for the same share of each braking as the
  wheels are locked; upstream showed zero resistance 100% of the time.
- **The Brake Trigger tab's settings do what their labels say.** Upstream overwrote the brake
  stiffness with the vibration values on every start.

**Other fixes**

- **Right trigger:** wheelspin only counts while you are on the throttle. Front-wheel slip under
  braking no longer makes the throttle trigger stiff.
- **Light bar:** in menus it shows the car class colour again. The performance index was read
  as one byte, and FH6's out-of-race packets are empty.
- **Settings file:**
  - If `RacingDSX.json` can't be read, RacingDSX warns you and leaves the file alone. Upstream
    silently replaced it with defaults.
  - Saves can't leave a half-written file.
- **Misc → Defaults** resets the game port to 5300. Upstream set 9999, which cut off telemetry.
- **Theme:** stock light Windows theme instead of upstream's half-applied dark one.

## Requirements

- Windows 10/11 x64
- [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/8.0). RacingDSX
  will not start without it.
- [DSX](https://store.steampowered.com/app/1812620/DSX/) (tested with v2 and v3.1) and a DualSense
  controller

## Setup

### 1. Get RacingDSX

Download the zip from [Releases](https://github.com/PawelSrangers/RacingDSX/releases/latest) and
extract it to a folder of its own (or build it yourself, see [Building](#building)). The window
title shows the version, e.g. `RacingDSX version: 0.7.0`.
RacingDSX keeps its settings in `RacingDSX.json` in the folder it is started from. When upgrading,
replace only `RacingDSX.exe` and `RacingDSX.dll.config` and keep your `RacingDSX.json`.

### 2. DSX

Settings → Controller → Networking: enable **UDP** and listen on port **6969**.

### 3. The game

**Forza Horizon 6 / 5:** Settings → HUD & Gameplay → Telemetry Output:
- **Data Out:** ON
- **IP:** `127.0.0.1`
- **Port:** `5300`

<details>
<summary>Forza Horizon 4 / Forza Motorsport 7 (extra loopback step)</summary>

Set Data Out as above. FM7 also needs **Data Out Packet Format: CAR DASH**.

These two are UWP games and can't send to `127.0.0.1` until loopback is allowed. Run this in an
admin PowerShell:

```powershell
# Forza Horizon 4
CheckNetIsolation LoopbackExempt -a -n="Microsoft.SunriseBaseGame_8wekyb3d8bbwe"
```

Or use the [AppContainer Loopback Utility](https://telerik-fiddler.s3.amazonaws.com/fiddler/addons/enableloopbackutility.exe):
tick the game, save. A warning about an orphan SID can be ignored.
</details>

<details>
<summary>DiRT Rally 1 / 2</summary>

Edit `C:\Users\<USER>\Documents\My Games\DiRT Rally X.0\hardwaresettings\hardware_settings_config.xml`:

```xml
<motion_platform>
    <udp enabled="true" extradata="3" ip="127.0.0.1" port="5300" delay="1" />
</motion_platform>
```
</details>

### 4. Run

Start DSX, RacingDSX and the game, in any order. Allow the firewall prompt if Windows shows one.
RacingDSX switches on by itself once it sees both the game and DSX running.

## Settings

Most settings are on the tabs in the window. Changes apply at once; **Apply** saves them.

**Brake Trigger tab**

| Setting | Meaning | Default |
|---|---|---|
| Min / Max Brake Vibration | Vibration frequency with one / all four wheels locked | 15 / 20 |
| Vibration Mode Start | How far the brake must be pressed (0–255) before a lock vibrates | 30 |
| Stiffness at Light / Full Brake | Vibration strength (0–255) | 5 / 150 |
| Min / Max Resistance | Resistance while the wheels roll (0–7) | 0 / 7 |
| Grip Loss | Not used for the brake any more; disabled | — |

With ABS on in the game the wheels rarely lock, so expect little vibration.

**Only in `RacingDSX.json`** (edit while RacingDSX is closed):

| Key | Meaning | Default |
|---|---|---|
| `DSXUpdateRateHz` | Messages per second sent to DSX (5–120). **If steering still sticks over Bluetooth, try 20 or 15.** Above 60 is not recommended. | 30 |
| `DisableAppCheck` | Start without waiting for the game and DSX processes | `false` |
| `DSXPort` | DSX's UDP port | 6969 |

## Known issues

- Closing RacingDSX does not release the triggers. Stop driving first, or they keep their last
  resistance until DSX resets them.
- If RacingDSX hits an unexpected error, it stops sending to DSX until restarted. The indicators
  can stay green when this happens.
- Turning *Disable App Check* off and on more than once per session may not take effect;
  restart RacingDSX.

## Building

Needs the [.NET 8 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0).

```bash
dotnet publish RacingDSX_source/RacingDSX.csproj -c Release -r win-x64 --self-contained false \
  -p:PublishSingleFile=true -p:PublishReadyToRun=true -o out
```

`--self-contained false` matters: the project defaults to a 70 MB self-contained build.

## For contributors

| Path | Contents |
|---|---|
| `RacingDSX_source/` | C# / WinForms / .NET 8 source |
| `specs/` | What the program must do: requirements with IDs (`REQ-BRAKE-003`, …) |
| `docs/adr/` | Why it is built this way: architecture decision records |
| `tools/` | Black-box test scripts. They run a sandboxed copy on ports 5310/6970 next to your real setup. |
| `recordings/` | Real FH6 telemetry used to test trigger feel |
| `AGENTS.md` | Full developer guide: invariants, testing, gotchas |

Quick checks:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_harness.ps1 -StopEarly
powershell -ExecutionPolicy Bypass -File tools/check_brake_replay.ps1 recordings/gravel_rally_20261011_200137.fzrec
```

Changes go through pull requests. Behaviour changes start as a change to `specs/`.

## Credits

- [cosmii02/RacingDSX](https://github.com/cosmii02/RacingDSX): the original project
- [DualSenseX](https://github.com/Paliverse/DualSenseX)
- [Forza-Telemetry](https://github.com/austinbaccus/forza-telemetry/tree/main/ForzaCore)
- [patmagauran](https://github.com/patmagauran)

## License

GPL-3.0, as upstream. See [RacingDSX_source/LICENSE](RacingDSX_source/LICENSE).
