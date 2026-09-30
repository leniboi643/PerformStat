# performstat

a lightweight, real-time performance monitor for apple silicon macs, inspired by
macmonitor and the minecraft f3 debug screen.

the statistics render **directly on the desktop** — behind all normal application
windows but above the wallpaper — in white monospace text with no background panel.
it lives in your menu bar for configuration.

```
performstat v1.0 — apple m4
macos 27.0 · 10 cores · 16 gb ram
cpu: 18%
gpu: 12%
memory: 7.2 / 16.0 gb
memory pressure: normal
swap: 0.0 gb
disk read: 42 mb/s
disk write: 8 mb/s
network ↓ 18 mb/s ↑ 3 mb/s
uptime: 2h 41m
thermal: nominal
```

## how the desktop overlay works

the overlay is a true desktop-level window, not a floating always-on-top panel:

```
wallpaper          (kCGDesktopWindowLevel base)
  ↓
performstat        (desktop level, transparent, click-through)
  ↓
desktop icons
  ↓
normal app windows (kCGNormalWindowLevel and above)
```

- transparent, borderless, shadowless `NSWindow` pinned to `kCGDesktopWindowLevel`
- `ignoresMouseEvents = true` — clicks pass straight through to the desktop
- `canJoinAllSpaces` + `stationary` — visible on every desktop/space, never moves
- never key/main, never in cmd-tab, no dock icon (`LSUIElement`)
- no wallpaper modification, no image generation — a real window-layer overlay

## statistics

| stat | source |
|---|---|
| cpu usage | `host_processor_info` tick deltas (all cores) |
| gpu usage | `IOAccelerator` registry `PerformanceStatistics` |
| memory used/total | `host_statistics64` + `hw.memsize` |
| memory pressure | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` (event-driven, zero polling) |
| swap | `vm.swapusage` sysctl |
| disk read/write | `IOBlockStorageDriver` registry byte counters |
| network ↓/↑ | `NET_RT_IFLIST2` sysctl byte counters (loopback excluded) |
| uptime | `kern.boottime` |
| chip / os version / cores | `sysctl` (computed once) |
| thermal state | `ProcessInfo.thermalState` (kernel thermal management) |
| battery | `IOPowerSources` (macbooks only; hidden on desktops) |
| temperatures & fans | SMC user client — see note below |

### sensor note (macos 26/27)

on current macOS builds (26+) apple gates the `AppleSMC` user client against
third-party processes: every key read returns `kIOReturnBadArgument`, with no
entitlement escape hatch for unsigned/ad-hoc apps. performstat ships a complete
SMC reader (`#KEY` enumeration → automatic temperature/fan key discovery →
sampling) that activates automatically on any system where the gate is absent
(older releases, or future ones that restore access). when gated, the overlay
reports `temps: unavailable (smc gated)` and shows the public kernel thermal
state instead, rather than inventing numbers.

## build

native arm64, zero dependencies — only `swiftc` and the command line tools:

```bash
cd PerformStat
./scripts/build.sh          # → build/PerformStat.app
open build/PerformStat.app
```

to install permanently:

```bash
cp -R PerformStat/build/PerformStat.app /Applications/
```

the app runs as a background/accessory application: no dock icon, launches
straight to the overlay + menu bar.

## menu bar

click the ▤ icon in the menu bar for all options:

- **show/hide performstat — or just press f3** anywhere, system-wide
- **statistics** — toggle each of the 13 stat lines individually
- **update interval** — 250 ms … 5 s
- **text size** — 10 … 20 pt
- **opacity** — 50 … 100 %
- **line spacing** — tight / 3 pt / 6 pt
- **position** — 8 presets (top left default) or custom x/y
- **screen** — main display or any secondary display
- **launch at login** — via `SMAppService`
- **reset settings**
- **quit**

all settings persist in standard `UserDefaults` (`local.performstat.app`).

### f3 toggle

a global carbon hotkey (`RegisterEventHotKey`, no accessibility permission) toggles
the overlay on **f3**. if your keyboard's media-mode maps f3 to mission control,
hold **fn+f3** — that sends the true f3 keycode, which performstat catches.

- one mach call per cpu sample; no allocations in the hot path beyond two small arrays
- sampling is tiered: cpu/gpu every tick, memory every 2 ticks, disk/net/battery
  every 4 ticks (min 2 s), thermal once per 5 s
- memory pressure is push-based from the kernel — no polling at all
- the view diffs the rendered lines and only repaints changed rows
- measured cost: ~0.1–0.5 % cpu, ~60 mb rss, no gpu work beyond compositing

## debugging

`PERFORMSTAT_DEBUG=1 ./PerformStat.app/Contents/MacOS/PerformStat` prints the
live stat lines to stderr for headless verification.

## layout

```
performstat/
├── app/            app entry, app delegate (lifecycle, space/screen notifications)
├── overlay/        desktop-level window, manager (sampling/format), f3-style view
├── statistics/     cpu, gpu, memory, disk, network, power, thermal, smc, pressure
├── settings/       userdefaults model + menu bar controller
├── resources/      Info.plist (LSUIElement background app)
└── scripts/        build.sh
```
