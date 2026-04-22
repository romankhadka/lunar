# Lunar

A macOS menu-bar app that changes the desktop wallpaper daily to reflect the current phase of the moon.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 15+ **or** the Swift Command Line Tools (`xcode-select --install`)

## Build and install

```bash
./scripts/install.sh
open ~/Applications/Lunar.app
```

Open the menu-bar moon icon and toggle **Launch at Login**.

## Custom phase images

Lunar ships with programmatically-generated placeholder images. To use your own:

1. Menu → **Open Phases Folder…**
2. Drop in 4096×4096 PNG files named:
   - `new.png`
   - `waxing_crescent.png`
   - `first_quarter.png`
   - `waxing_gibbous.png`
   - `full.png`
   - `waning_gibbous.png`
   - `last_quarter.png`
   - `waning_crescent.png`
3. Menu → **Refresh Now**

Images should be square, RGB, with the moon centered on a near-black background. Northern Hemisphere orientation (waxing light on the right, waning light on the left).

## Development

```bash
swift test         # run all tests
swift build        # build executable
./scripts/build.sh # assemble Lunar.app
```

## Logs

`~/Library/Logs/Lunar/lunar.log` (rotates at 1 MB).

## Design notes

See `docs/superpowers/specs/2026-04-21-lunar-design.md` for the full design spec.
