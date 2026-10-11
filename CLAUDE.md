# RacingDSX — DualSense adaptive triggers for Forza

Patched fork of [cosmii02/RacingDSX](https://github.com/cosmii02/RacingDSX) (upstream version 0.6.7),
fixed for **Forza Horizon 6**.

Git repo, branch `main`, no remote. The first commit (tag `upstream-0.6.7`) is the unmodified
upstream source, so `git diff upstream-0.6.7 -- RacingDSX_source` shows everything this fork
changes. `RacingDSX_exe/` is deliberately **not** in git (see `.gitignore`): it is the deployed
build plus the user's live config, and no checkout or reset may ever touch it. Back up anything
you replace in there by hand.

## Layout

| Path | What it is |
|---|---|
| `RacingDSX_source/` | C# / WinForms / .NET 8 source. Edit here. |
| `RacingDSX_exe/` | The build the user actually runs. `RacingDSX.json` here is their live tuned config — **never overwrite it**, only add fields. |
| `RacingDSX_exe/backup_original/` | Stock upstream exe + config, for A/B testing and rollback. |
| `RacingDSX_exe/backup_prev/` | The exe that was deployed before the latest one. |
| `recordings/` | Real FH6 telemetry captured with `tools/record_forza.ps1` (`.fzrec` tracked, `.csv` regenerated). |
| `tools/` | Test harness (see below). |
| `docs/adr/` | Architecture Decision Records — why things are the way they are. Read the relevant ADR before changing a decision it covers; to reverse one, write a new ADR that supersedes it rather than editing the old one. |

## How the whole thing fits together

RacingDSX does **not** touch sticks or buttons. It only tells DSX what resistance to put on
the triggers and what colour to make the light bar.

```
Forza  --UDP 5300 (telemetry)-->  RacingDSX  --UDP 6969 (JSON)-->  DSX  --HID-->  DualSense
                                                                    |
                                                                    +--> ViGEm virtual X360 pad --> Forza reads sticks here
```

The sticks reach the game through **DSX's** virtual pad. So the only way RacingDSX can break
steering is by overloading DSX until its controller thread stalls and the virtual pad stops
updating — which is exactly the bug that was fixed. Keep that in mind before adding anything
that increases outbound traffic.

Code path per telemetry packet, all in [`RacingDSXWorker.Run`](RacingDSX_source/RacingDSXWorker.cs):

`client.Receive` → `AdjustToBufferType` (sets `FMData.BufferOffset` from packet length) →
`Parser.ParsePacket` → `DataPacket` → `Get*Instruction` → `Instruction[]` → JSON → `senderClient.Send`

## The FH6 rate invariant — do not regress this

**FH4/FH5 send telemetry at a fixed 60 Hz. FH6 sends it at the game's frame rate** (130–240/s).
Upstream sent *three separate UDP messages per telemetry packet*, so FH6 pushed ~420 msg/s at
DSX, its HID queue backed up, and the emulated pad latched on its last state — the user saw
steering "stick" at random with the stick already released.

Three things in `RacingDSXWorker` hold the line. Breaking any of them brings the bug back:

1. `IsSendDue()` caps outbound rate at `Config.DSXUpdateRateHz` (default 30).
2. `SendData` packs all instructions into **one** packet via `Combine`. Never go back to a
   `Send` per instruction.
3. `Send` skips payloads identical to the last one (with a 1 s keep-alive).
4. `HoldVibration`/`ApplyHeldVibration` keep the strongest trigger vibration seen between
   sends and deliver it at the next slot. Without this the rate limit swallows 1–2 frame
   wheel locks and wheelspin (measured 8/19 delivered vs 19/19 on stock). See ADR-0008.

Filters still run on every telemetry frame — only the *send* is throttled, so EWMA smoothing
keeps seeing the full stream. If you add a new instruction type, add it to the `Combine` call,
don't send it separately.

Second FH6 difference: **the stream stops entirely** in menus, pause, replay and after a race,
where FH4/FH5 kept streaming with `IsRaceOn = 0`. `client.Client.ReceiveTimeout` +
`OnTelemetryIdle()` release the triggers when that happens.

## Packet formats

`AdjustToBufferType` dispatches purely on datagram length:

| Bytes | Game | `FMData.BufferOffset` |
|---|---|---|
| 232 | FM7 sled | rejected (no dash data) |
| 264 | Dirt Rally 1 | 0 |
| 311 | FM7 dash | 0 |
| 331 | FM8 / FM2023 dash | 0 |
| 324 | **FH4 / FH5 / FH6** | 12 |

FH6's layout is byte-for-byte identical to FH5. The 12 bytes the offset skips are `CarGroup`,
`SmashableVelDiff`, `SmashableMass`, sitting between `NumCylinders` and `PositionX`.
Official reference: [FH6 Data Out docs](https://support.forza.net/hc/en-us/articles/51744149102611-Forza-Horizon-6-Data-Out-Documentation).

`FMData.BufferOffset` is a **mutable global static** applied to every dash-section accessor.
It is fine today because one worker runs at a time; if you ever run two parsers concurrently,
this is the first thing that will break.

## Build

Requires the .NET 8 SDK (8.0.425 is installed; only the runtime ships by default).

```bash
dotnet build RacingDSX_source/RacingDSX.csproj -c Release
```

To produce the exe in the shipped layout — framework-dependent single file, ~3.6 MB. The
csproj forces `SelfContained=true` for Release, so the override is required or you get a
70 MB self-contained bundle that does not match what the user has:

```bash
dotnet publish RacingDSX_source/RacingDSX.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -p:PublishReadyToRun=true -o <outdir>
```

Then copy `RacingDSX.exe` and `RacingDSX.dll.config` into `RacingDSX_exe/`, leaving
`RacingDSX.json` alone.

Known-benign build warnings: `MSB4011` (duplicate `Microsoft.Common.props` import on csproj
line 3), `CS0108` on `NameForm.CancelButton`, `CS0219` on an unused `avgAccel`. All predate
this fork; don't "fix" them incidentally.

## Testing

There is no unit test project. Everything in `tools/` is black-box: it runs a **sandboxed copy**
of an exe in `%TEMP%` with app check off and its own ports (game 5310, DSX 6970), so the user's
real DSX, RacingDSX and game can stay open, and it only ever stops its own process. Never point
a test at 5300/6969 or kill RacingDSX/DSX by name.

**Real data first.** For anything about trigger feel, replay the user's recordings:

```bash
powershell -ExecutionPolicy Bypass -File tools/check_brake_replay.ps1 recordings/gravel_rally_20261011_200137.fzrec
```

It replays the `.fzrec` with original timing and prints, per braking event, lock% (frames with a
wheel turning at < 35% of car speed) next to the share of time the brake trigger spent in
vibration / resistance / zero. On the current build vibration tracks lock% within a few points;
stock gives `ZERO 100%` on gravel. Add `-ExePath ...` to A/B. Shares are time-weighted on purpose:
dedupe means steady states are not resent, so counting packets under-weights them.

**Rate and idle regression:**

```bash
powershell -ExecutionPolicy Bypass -File tools/run_harness.ps1 -StopEarly
```

Expected: **~28 packets/s**, three instructions each (stock: ~419/s, one each). Last packet
must be the trigger release `{"instructions":[{"type":1,"parameters":[0,1,0,0,0]},{"type":1,"parameters":[0,2,0,0,0]}]}`.

**Synthetic brake scenarios:** `tools/probe_brake.ps1 [-ExePath ...]` holds fixed brake / slip /
locked-wheel combinations and fires 14 ms lock-ups; expect resistance while rolling, vibration
16→20 Hz for 1→4 locked wheels, and every lock-up delivered. `fake_forza.ps1` takes `-Brake`,
`-Slip`, `-LockWheels`, `-SpikeSlip`, `-Port`. It rolls its wheels at car speed (0.32 m radius)
and keeps them on the ground; without that every wheel would look locked to the parser.

**Recording real data:** `tools/record_forza.cmd` (or `record_forza.ps1 -Name x`) captures raw
telemetry to `recordings/<name>_<timestamp>.fzrec`. The user's RacingDSX must be closed for that
(it owns 5300); the game can stay running. `decode_recording.ps1` → CSV with every field,
`analyze_braking.ps1` → per-event lock/slip table, `replay_recording.ps1` → plays a recording back.
Ask for a recording rather than guessing what the game sends; fakes are only as good as our
assumptions (the gravel bug was invisible until real data showed lock slip of 3.15, not > 4).

For UI changes, start the app and screenshot it — that is the only way to check a layout or
theme edit, since the designer file can't be opened here:

```bash
powershell -ExecutionPolicy Bypass -File tools/screenshot_ui.ps1 -RelX 340 -RelY 66 -OutFile brake.png
```

`-RelX/-RelY` click before capturing (tab strip is at y=66). Check every tab, not just the one
you changed.

## Gotchas

- **Config lives in the working directory.** `ConfigHandler` reads `RacingDSX.json` by relative
  path, so the exe's CWD decides which config it loads. New `Config` fields need only a property
  initialiser; missing keys in an old JSON deserialise to the default and get written back on save.
- **App check gates everything.** The worker only starts once `AppCheckThread` sees a process from
  `executableNames` *and* one named `DSX`/`DualsenseX`. FH6's process is `ForzaHorizon6`. If the
  user reports "nothing happens at all", check this before looking at the telemetry path.
  `DisableAppCheck: true` bypasses it.
- **Verbose messages are hidden by default.** `Report` keeps entries where
  `x.verboseLevel <= settings.VerboseLevel`, and `VerboseLevel.Off = 0`, so `Limited` messages
  never render until the user raises the level. Diagnostics that must always show should be sent
  as a plain `RacingDSXReportStruct(string)`.
- **Sockets are static fields** (`client`, `senderClient`, `ipEndPoint`, `endPoint`) shared across
  worker instances. Two concurrent workers will close each other's sockets. `StartRacingDSXThread`
  rebuilds the `CancellationTokenSource` per run and `StopRacingDSXThread` joins, specifically to
  keep that from happening.
- **`Instruction.Parameters` is a positional `object[]`** matching DSX's UDP API; meaning depends
  entirely on index and on the `InstructionType`. `ParametersConverter` serialises it, coercing
  everything numeric to int via `ToSafeInt32` (NaN → 0, out of range → clamped) so a bad telemetry
  value cannot throw out of the send path.
- **Brake lock = wheel speed vs car speed, never tyre slip.** Forza normalises slip by the
  surface's grip, so a fully locked wheel reads ~5.6 on asphalt but ~3.15 on gravel; any slip
  threshold works on one surface and not the other. `GetBrakeLock` compares each grounded wheel's
  ground speed (`ForzaParser` learns the rolling radius while cruising) with `Speed`. Brake
  `GripLossValue` is unused since ADR-0009, and `Min/MaxVibration` now mean frequency at one /
  all four wheels locked. The throttle side still uses the old slip logic.
- **`SwitchActiveProfile` runs once a second.** `AppCheckThread` reports every 1000 ms and
  `AppCheckReporter` calls it each time, with `null` whenever no game is running. It must
  early-return when the requested profile already matches, or every tick rebuilds both lists,
  rewrites the config to disk and restarts the worker thread — which also resets
  `ExecutableListBox.DataSource` and snaps its selection back to item 0. Any new work added to
  that method inherits the same once-a-second cost.
- **UI is WinForms designer-generated.** `UI.Designer.cs` is not hand-editable without Visual
  Studio, which is not installed here. Prefer config-file settings over new controls. Bulk
  property changes are best done as a scripted line filter over the designer file, then verified
  by building and screenshotting — see below.
- **Theme is the stock light Windows look.** Upstream hard-coded a dark theme
  (`BackColor = FromArgb(18,18,18)` plus `ForeColor = White` on ~150 controls) but applied it
  inconsistently: the form went dark while the tab strip and status bar stayed light, and the
  `profilesGroupBox` title was black-on-black. Those 159 lines were removed and the nine
  `UseVisualStyleBackColor = false` flipped back to `true`. The original is
  `git show upstream-0.6.7:RacingDSX_source/UI.Designer.cs`. Don't reintroduce per-control
  colours; if a dark theme is ever wanted again, do it at the form level and fix the tab
  control and status strip too.

## Conventions

Match the surrounding style: `PascalCase` methods, `b`-prefixed booleans (`bRunning`,
`bRaceOn`), braces on their own line. The upstream code is inconsistent and has commented-out
blocks — leave them; don't reformat or tidy files you aren't otherwise changing, it makes
diffing against upstream harder.
