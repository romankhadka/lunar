# Lunar

A tiny macOS menu-bar app that paints your desktop wallpaper with today's moon phase — updated silently every day.

Ships with 8 public-domain NASA moon photographs (one per phase), cycling automatically as the moon moves through its synodic cycle. A small overlay in the bottom-right of the wallpaper shows the current phase, illumination percentage, and date.

## Features

- **Daily auto-update.** Runs once per day plus on every wake-from-sleep, so you always see today's moon.
- **Every connected display.** Paints the same wallpaper on all screens; re-applies when monitors are plugged or unplugged.
- **Light and dark appearance.** Same wallpaper in both modes — observes macOS appearance changes and keeps both slots in sync.
- **Custom imagery.** Ships with NASA photos; drop your own 8 PNGs into a folder to replace them.
- **Minimal menu-bar UI.** Moon icon; click for today's phase, next phase, refresh, open-log, launch-at-login, quit. No Dock icon.
- **No network. No telemetry. No dependencies.** Pure local, ~20 MB RAM, zero network calls.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 15+, or the Swift Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/romankhadka/lunar.git
cd lunar
./scripts/install.sh
open ~/Applications/Lunar.app
```

Click the moon icon in the menu bar, toggle **Launch at Login**, and you're done.

## Custom phase images

Lunar ships with NASA moon photography. To use your own imagery instead:

1. Click the menu-bar moon → **Open Phases Folder…**
2. Drop in 8 square PNGs named exactly:
   - `new.png`
   - `waxing_crescent.png`
   - `first_quarter.png`
   - `waxing_gibbous.png`
   - `full.png`
   - `waning_gibbous.png`
   - `last_quarter.png`
   - `waning_crescent.png`
3. Click **Refresh Now**.

Images should be square, RGB, with the moon centered on a near-black background. Northern Hemisphere orientation (waxing light on the right, waning light on the left). Any square resolution works — the app aspect-fits to your display.

## How it works

Lunar computes the current moon phase locally using a simplified form of Jean Meeus's *Astronomical Algorithms* (ch. 48), anchored to a recent reference new moon. The phase is bucketed into one of 8 named phases. The matching base image is composited with a thin overlay (`Waxing Gibbous · 87% · Apr 23`) in the bottom-right corner, scaled to the largest connected display, and applied to every screen via `NSWorkspace.setDesktopImageURL`.

To defeat macOS's wallpaper cache (a known Sonoma+ quirk), after each apply the app politely restarts `WallpaperAgent` so the visible desktop repaints.

## Logs

`~/Library/Logs/Lunar/lunar.log` — rotates at 1 MB. Menu → **Open Log** opens it in Console.

## Development

```bash
swift test         # 40 unit tests, ~0.1s
swift build        # debug build
./scripts/build.sh # assemble Lunar.app
```

Module layout (in `Sources/Lunar/`):

| File | Responsibility |
|---|---|
| `PhaseName.swift` | 8-case enum; raw values double as filename stems |
| `PhaseCalculator.swift` | Julian Day → synodic age → illumination → phase name |
| `ImageProvider.swift` | Override-folder > bundle resolution |
| `Compositor.swift` | Core Graphics composite + Core Text overlay |
| `WallpaperSetter.swift` | Dated-filename file store + NSWorkspace apply |
| `Logging.swift` | `os.Logger` categories + rolling file log |
| `AppCoordinator.swift` | Orchestrates all of the above with idempotency |
| `MenuBarController.swift` | SwiftUI `MenuBarExtra` view |
| `App.swift` | `@main`, AppDelegate, schedule and event subscriptions |

## Credits

- Moon imagery: NASA Scientific Visualization Studio / Goddard Space Flight Center. Public domain.
- Phase math: derived from Jean Meeus, *Astronomical Algorithms* (2nd ed., Willmann-Bell, 1998).

## License

MIT — see [LICENSE](LICENSE). NASA imagery is U.S. federal-government work and is in the public domain independently of the MIT license.
