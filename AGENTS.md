# AGENTS.md

Instructions for AI agents (Claude Code, Codex, Cursor, etc.) working in this repository.
The first half is project knowledge (what RacingDSX is, invariants, build, test, gotchas);
the second half is the process (specs, ADRs, PRs) from the `scaffold-agentic-project` template.

## RacingDSX — DualSense adaptive triggers for Forza

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
| `docs/adr/` | Architecture Decision Records — why things are the way they are. Read the relevant ADR before changing a decision it covers; to reverse one, write a new ADR that supersedes it rather than editing the old one. See [ADRs](#architecture-decision-records-adr) below. |
| `specs/` | Feature specs — the source of truth for observable behavior. See [Spec-driven development](#spec-driven-development). |
| `.github/` | PR templates: implementation (default) and spec change. |
| `config/secrets.env.tpl` | 1Password reference template from the project scaffold. The app has no secrets today; keep it as a placeholder. |

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
  settings (ADR-0009/0010): `Min/MaxVibration` = frequency at one / four wheels locked;
  `VibrationModeStart` = minimum brake input (0–255) for lock vibration; `MinStiffness` is used
  at *full* brake and `MaxStiffness` at *light* brake (the UI labels say so); `GripLossValue` is
  unused and its control is disabled. The throttle side still uses the old slip logic.
- **UI handlers come in pairs and must touch only their own pair.** Each setting has a slider
  and a number box whose handlers update each other. Upstream's brake stiffness box read the
  *vibration* box, and because `SwitchDisplayedProfile` sets every box on start, it silently
  overwrote stiffness with vibration values on each launch. When adding or editing a handler,
  check it names its own controls; a mistake here corrupts the user's saved config.
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

## Communication style

Be brutally honest, straightforward, and logical. Challenge assumptions, question
reasoning, call out flaws, contradictions, and unrealistic ideas. No empty praise,
no sugarcoating, no vague advice — hard facts, clear reasoning, actionable feedback.
Push back whenever necessary.

## Spec-driven development

Specs in `specs/` are the source of truth for behavior. Code follows specs, never
the other way around. See ADR-0012.

### Layout

- One spec per feature: `specs/<feature-slug>.md`, copied from `specs/_template.md`.
- Each requirement has a stable ID `REQ-<FEATURE>-NNN`. IDs are never reused or
  renumbered. Removed requirements are marked `Status: Removed`, not deleted.
- Spec = *what* the system does (observable behavior, acceptance criteria).
  ADR = *how/why* it is built. Don't put implementation details in specs.
- The current specs were written on 2026-10-19 from behavior that had already shipped
  (ADR-0001…0010, real recordings, `tools/` results). They start as `Draft` until
  the owner approves them.

### Spec lifecycle

`Draft` → `Approved` → `Implemented` → `Deprecated`

- Only `Approved` specs may be implemented.
- A spec with blocking open questions cannot be `Approved`.
- Status transitions are spec changes and go through a spec PR.

### Hard rules for agents

1. **Never modify `specs/` in an implementation PR.** Not even "small fixes".
2. **If the spec must change** (wrong, incomplete, contradicts reality, or the user
   asks for new behavior): stop, explicitly tell the user what you want to change,
   why, and what it affects. Then open a **separate spec PR** using
   `.github/PULL_REQUEST_TEMPLATE/spec-change.md`. Implementation of changed
   behavior waits until the spec PR is merged.
3. **Ambiguity is a blocker, not a judgment call.** If a requirement can be read
   more than one way, ask. Do not pick an interpretation silently.
4. **No scope creep.** Do not implement behavior not covered by a requirement.
   Items under `Non-goals / Out of scope` are forbidden.
5. **Traceability.** Every implementation PR lists the requirement IDs it covers.
   Tests reference the requirement ID they verify (in the test name or a comment).
   Here the tests are the black-box scripts in `tools/`: name the REQ IDs in the
   script's header comment and in the PR's Testing section.
6. **Code vs spec mismatch.** If code disagrees with the spec, the code is the bug
   — fix it in an implementation PR. If you believe the spec is the bug, rule 2.
7. **Spec vs ADR conflict.** Flag it to the user. Do not resolve it in either
   direction on your own.
8. **Agents never merge PRs.** The project has a single maintainer (the owner);
   the owner's merge of a spec PR *is* the approval. `gh pr merge` is denied in
   `.claude/settings.json`.

Changes without behavior impact (refactoring, tooling, CI, docs) don't need a spec,
but must not change observable behavior.

## Pull requests

Every PR uses a template from `.github/`:

| PR type | Template | How |
|---|---|---|
| Implementation, fix, refactoring, infra, docs | `.github/pull_request_template.md` | applied by default |
| Spec change | `.github/PULL_REQUEST_TEMPLATE/spec-change.md` | `gh pr create --template spec-change.md` |

- Fill every section. Write `none` explicitly instead of deleting required sections.
- A PR is either a spec PR or an implementation PR — never both.
- One logical change per PR. Split large PRs.
- Do not commit or open PRs unless the user explicitly asks.
- The repo has no remote yet. Until it does, apply the same split to commits: a commit
  touches either `specs/` or code, never both, and its message carries the PR template's
  Spec traceability lines.

## Architecture Decision Records (ADR)

Every significant architectural decision MUST be recorded as an ADR in `docs/adr/`.

### What counts as "significant"

Write an ADR when a decision:
- picks a technology, framework, library, or external service;
- defines a data model, API contract, or integration boundary;
- affects security, secrets handling, deployment, or infrastructure;
- is expensive to reverse, or constrains future decisions.

Do not write ADRs for trivial, easily reversible choices (variable names, formatting).

### Format

- File name: `docs/adr/NNNN-short-kebab-title.md` (sequential, zero-padded, never reused).
- Copy `docs/adr/0000-template.md`. Body text is in Russian like the existing ADRs;
  keep the template's section headings and `Relations` keys in English so they stay
  machine-readable.
- ADR-0001…0010 predate the template and use Russian headings. ADR-0011 added a
  `Relations` section to them on 2026-10-19; their decisions were not edited.
- ADRs are immutable once `Accepted`. To change a decision, write a new ADR that
  `Supersedes` the old one and set the old one's status to `Superseded by NNNN`.
  Only the status line of an old ADR may be edited.
- Add every new ADR to the index in `docs/adr/README.md`.

### Relations (mandatory)

Every ADR has a `Relations` section with machine-readable links to other ADRs:

- `Depends-on: NNNN` — this decision assumes NNNN holds.
- `Supersedes: NNNN` — this decision replaces NNNN.
- `Constrains: NNNN` — this decision limits options in NNNN.
- `Related: NNNN` — informational link only.

Use `none` if there are no relations. These links form the dependency graph of
the architecture — keep them accurate.

### Agent duties

- **Before proposing a change** that touches an area covered by an ADR, read
  `docs/adr/`, build the dependency graph from `Relations`, and explicitly list
  every ADR (and the components it describes) that would break or need revision.
  Do not silently contradict an accepted ADR.
- **When making a significant decision**, draft the ADR in the same change.
- **When superseding**, walk all ADRs that `Depends-on` the superseded one
  transitively and flag each as needing review.

### Decision trees

No separate decision-tree artifacts. Alternatives and the reasoning for rejecting
them go into the ADR's `Considered options` section. If a decision genuinely has
multi-level branching (choice A forces sub-choices B/C), add a Mermaid `flowchart`
inline in that ADR — not as a standalone file.

## Secrets

- Secrets live in 1Password only. Never commit real secret values.
- `config/*.tpl` files contain only `op://` references; resolve them at runtime
  with `op run --env-file=config/secrets.env.tpl -- <command>` or
  `op inject -i config/secrets.env.tpl -o config/secrets.env`.
- Resolved files (`config/*.env`) are git-ignored.
- RacingDSX itself uses no secrets (local UDP only). `SECRET_PLACEHOLDER` stays until
  something actually needs one.
