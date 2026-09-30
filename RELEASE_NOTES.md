# PerformStat v1.0

a live f3-style performance hud for your mac desktop — real-time cpu, gpu, memory,
disk, network, uptime and thermal stats rendered **directly on the wallpaper**,
behind every window. press **f3** to toggle it anywhere.

![macos](https://img.shields.io/badge/macOS-13%2B-black) ![arch](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-black) [![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## install

1. download **`PerformStat-v1.0-macos.zip`** below
2. unzip and drag **PerformStat** into **Applications**
3. first launch: right-click → **Open** (ad-hoc signed, so Gatekeeper needs a nudge)
4. the hud appears on your desktop immediately — press **f3** (or fn+f3) to toggle

verify the download:

```bash
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

## what's new

- desktop-level overlay: above the wallpaper, below every window, click-through
- f3 global hotkey toggle
- 11 live statistics — cpu, gpu, memory, pressure, swap, disk i/o, network, uptime, thermal state, battery, system info
- menu bar controller: per-stat toggles, interval, text size, opacity, spacing, 8 position presets + custom x/y, display picker, launch-at-login
- settings persist in UserDefaults
- universal binary (apple silicon + intel), ~0.2% cpu

## notes

- no dock icon; PerformStat lives in your menu bar (▤ / logo icon)
- battery line appears automatically on macbooks
- free & open source — MIT
