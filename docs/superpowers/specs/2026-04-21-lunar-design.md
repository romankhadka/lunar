# Lunar — Design Spec

**Date:** 2026-04-21
**Status:** Approved for implementation planning
**Target platform:** macOS 14 (Sonoma) and newer
**Language:** Swift 5.9+ / SwiftUI + AppKit

## 1. Purpose

Lunar is a native macOS menu-bar app that changes the desktop wallpaper daily to reflect the current phase of the moon. It computes the phase locally, composites a phase-appropriate image with a small daily overlay (phase name · illumination % · date), and applies it as the system wallpaper across all connected displays, silently and automatically.

The app is a personal utility, distributed as source for local build. No network access, no telemetry, no App Store.

## 2. Design decisions (answers to key questions)

| # | Decision | Chosen |
|---|---|---|
| 1 | UX model | Menu-bar app (minimal UI) |
| 2 | Phase granularity | Hybrid: 8 base images + daily overlay text |
| 3 | Overlay style | Minimal text in bottom-right corner |
| 4 | Scheduling trigger | Login + wake-from-sleep + daily timer |
| 5 | Multi-display | All screens, all Spaces, same wallpaper |
| 6 | Light/dark mode | Same wallpaper in both modes |
| 7 | Image source | Bundled defaults + override folder |
| 8 | Hemisphere | Northern Hemisphere only (hard-coded) |
| 9 | Image spec | 4096×4096 square PNGs, black background |
| 10 | Architecture | Native Swift + SwiftUI menu-bar app |
| 11 | Name | Lunar |

## 3. High-level architecture

A single `.app` bundle (`Lunar.app`) running as an `LSUIElement` (menu-bar only, no Dock icon). It launches at login via `SMAppService.mainApp` and remains resident to observe system events. Memory footprint expected ~20 MB.

The app is organized into four isolated modules plus a coordinator, each with a clear single purpose and a narrow public API. A thin menu-bar controller reads state from the coordinator and exposes a handful of user actions.

```
┌────────────────────────────────────────────────────────────┐
│                      AppCoordinator                        │
│   (owns schedule, wires modules, publishes state)          │
└─────┬──────────┬──────────┬──────────┬──────────┬──────────┘
      │          │          │          │          │
      ▼          ▼          ▼          ▼          ▼
 PhaseCalc  ImageProvider  Compositor  Wallpaper  MenuBar
 (pure)     (disk I/O)     (CoreGfx)   Setter     Controller
                                       (NSWorkspace)
```

## 4. Modules

### 4.1 `PhaseCalculator`

**Purpose:** Pure function, `Date → MoonPhase`. No I/O.

**Algorithm:** Jean Meeus, *Astronomical Algorithms* (2nd ed.), chapter 48 ("Illuminated Fraction of the Moon's Disk"). The simplified phase-angle form is implemented over a mean synodic period anchored to a recent reference new moon. Sufficient for 8-phase bucketing across the entire foreseeable run window; illumination percentages are approximate to within ~10% near the quarters and within ~2% near new/full. The implementation computes the Sun's and Moon's ecliptic positions, derives the phase angle from their elongation, and from that computes illumination fraction. Synodic age is derived from the same intermediate quantities. ~60 lines of Swift, zero dependencies.

**Timezone handling:** Input `Date` is normalized to local noon before conversion to Julian Day. Using noon rather than midnight avoids day-boundary flicker where a phase-bucket transition would occur at 00:00.

**Public API:**

```swift
struct MoonPhase {
    let date: Date                // Input date (normalized to local noon)
    let age: Double               // Days since last new moon (0 … 29.53)
    let illumination: Double      // 0.0 … 1.0 (fraction of disk lit)
    let phaseName: PhaseName      // One of 8 canonical phases
}

enum PhaseName: String {
    case new              = "new"
    case waxingCrescent   = "waxing_crescent"
    case firstQuarter     = "first_quarter"
    case waxingGibbous    = "waxing_gibbous"
    case full             = "full"
    case waningGibbous    = "waning_gibbous"
    case lastQuarter      = "last_quarter"
    case waningCrescent   = "waning_crescent"
}
// rawValue maps directly to the phase filename stem; ImageProvider
// uses it as "<rawValue>.png" for both override and bundle lookup.

enum PhaseCalculator {
    static func phase(for date: Date) -> MoonPhase
}
```

**Phase-name bucketing** — eight equal buckets, each 29.53 ÷ 8 ≈ 3.69 days wide, centered on the four astronomical events (new at age 0, first quarter at 7.38, full at 14.77, last quarter at 22.15). "New" wraps across the cycle boundary.

| Age (days) | Phase |
|---|---|
| 27.69 – 29.53 **and** 0.00 – 1.85 | New |
| 1.85 – 5.54 | Waxing Crescent |
| 5.54 – 9.22 | First Quarter |
| 9.22 – 12.91 | Waxing Gibbous |
| 12.91 – 16.61 | Full |
| 16.61 – 20.30 | Waning Gibbous |
| 20.30 – 23.99 | Last Quarter |
| 23.99 – 27.69 | Waning Crescent |

Implementation note: bucket by `(age + halfBucket) mod 29.53` so the New-moon wrap is handled arithmetically rather than with a special case.

### 4.2 `ImageProvider`

**Purpose:** Resolve the base PNG for a given `PhaseName`, honoring an override folder.

**Resolution order (first hit wins):**
1. `~/Library/Application Support/Lunar/phases/<phase>.png`
2. Bundled resource `Lunar.app/Contents/Resources/phases/<phase>.png`

**Filename convention (fixed, snake_case):**
`new.png`, `waxing_crescent.png`, `first_quarter.png`, `waxing_gibbous.png`, `full.png`, `waning_gibbous.png`, `last_quarter.png`, `waning_crescent.png`

**Image spec (documented in README):** 4096×4096 PNG, RGB, moon centered on near-black (`#000000`–`#0A0A0A`) background. The app does not validate dimensions — it scales at composite time. Northern Hemisphere orientation (waxing on the right, waning on the left).

**First-run setup:** On first launch, the app creates `~/Library/Application Support/Lunar/phases/` if absent. It does **not** auto-copy bundled images into it — the folder stays empty until the user drops overrides in. Empty folder unambiguously means "use bundled."

**Public API:**

```swift
struct ImageProvider {
    let supportDirectory: URL   // ~/Library/Application Support/Lunar
    func baseImage(for phase: PhaseName) throws -> CGImage
    func openOverrideFolderInFinder()
}
```

**Errors:** Missing or malformed override falls back silently to bundled. Missing bundled image throws — `AppCoordinator` logs and skips the update. Never crashes.

### 4.3 `Compositor`

**Purpose:** Take a base `CGImage` + `MoonPhase` + target canvas size → final wallpaper `CGImage` with overlay baked in.

**Output canvas:** Resolution of the largest connected display by pixel area (queried per `updateWallpaper()` call via `NSScreen.screens`; `max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })`). The same composited image is written once and applied to every screen; macOS scales it per-display. This avoids rendering N images for N screens.

**Composition steps:**
1. Create a `CGContext` at target canvas size, fill with pure black (`#000000`).
2. Scale-and-center the 4096×4096 base using aspect-fit. On landscape canvases (the common case: MacBook, 5K, ultrawide) the square source pillarboxes with black bars on the left and right; on portrait canvases it would letterbox on top and bottom. Either way, the seam is invisible because base images are black-backgrounded and the canvas fill is black.
3. Draw overlay text in the bottom-right corner with a margin equal to ~1.25% of canvas width (≈ 64 px on a 5120×2880 canvas).
4. Flatten to `CGImage`.

**Overlay text format:**
```
Waxing Gibbous · 87% · Apr 21
```

- Font: SF Pro Text Light (via `NSFont.systemFont(ofSize:weight: .light)`), size = 1.5% of canvas height (≈ 43 pt on a 5120×2880 canvas)
- Color: `#E8E8E8` at 70% opacity
- Letter-spacing: +0.5 pt
- No background plate, no drop shadow
- Date format: `MMM d` using the system locale

**Rationale:** Bottom-right survives the menu bar (top) and Dock (bottom-middle). 70% opacity keeps it legible without shouting. Canvas-relative sizing holds up on any display.

**Public API:**

```swift
struct Compositor {
    func composite(base: CGImage, phase: MoonPhase, canvasSize: CGSize) -> CGImage
}
```

### 4.4 `WallpaperSetter`

**Purpose:** Persist the composited image and apply it to every connected display.

**File layout:**
- Written to `~/Library/Application Support/Lunar/current/YYYY-MM-DD.png`
- Last 7 days retained; older files pruned on each write.

**Why dated filenames:** macOS has a known bug (`sindresorhus/macos-wallpaper` issue #44, reproduced on Sonoma 14.2.1) where calling `setDesktopImageURL` with the same URL whose file *contents* have changed fails to refresh the desktop. Using a fresh URL each day sidesteps it.

**Apply logic:**

```swift
for screen in NSScreen.screens {
    try NSWorkspace.shared.setDesktopImageURL(
        fileURL,
        for: screen,
        options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]
    )
}
```

**Light/dark mode behavior:** `NSWorkspace.setDesktopImageURL` only updates the appearance slot that is currently active. There is no public API to set both slots in a single call (confirmed via 2024–2026 research on Apple Developer Forums and `sindresorhus/macos-wallpaper`). To satisfy "same wallpaper in both modes":

- Every `updateWallpaper()` call sets the current appearance's slot.
- The app subscribes to appearance changes via KVO on `NSApp.effectiveAppearance` (there is no `NSApplication.didChangeEffectiveAppearanceNotification`; KVO is the supported mechanism). On appearance flip, `reapplyToday()` is invoked so the other slot gets today's image.
- In steady state, both slots hold today's image. The only edge case: immediately after the first update of the day, the opposite-mode slot still shows yesterday's image until an appearance change occurs — invisible in practice for a personal app.

**Multi-display:** Iterating `NSScreen.screens` covers all displays. The app also observes `NSApplication.didChangeScreenParametersNotification` and re-applies when monitors are plugged or unplugged.

**Permissions / signing:** No TCC prompts required. `setDesktopImageURL` on files under the user's own `Application Support` directory is unprivileged. The app ships non-sandboxed and ad-hoc signed (`codesign -s -`) — sufficient for personal local use. Developer ID would only matter for distribution.

**Do not** touch private state (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, the `WallpaperAgent` container on Sequoia/Tahoe) — formats are undocumented and volatile.

**Public API:**

```swift
struct WallpaperSetter {
    func apply(image: CGImage, for date: Date) throws
    func reapplyToday() throws
}
```

## 5. `AppCoordinator` & schedule

**Trigger matrix** — all triggers funnel through the same idempotent `updateWallpaper()`:

| Trigger | Source | Rationale |
|---|---|---|
| App launch | `applicationDidFinishLaunching` | First run after login |
| Wake from sleep | `NSWorkspace.didWakeNotification` | Laptop opened mid-day |
| Screen change | `NSApplication.didChangeScreenParametersNotification` | New monitor attached |
| Appearance change | KVO on `NSApp.effectiveAppearance` | Sync other light/dark slot |
| Daily at 06:00 local | `Timer` rescheduled each fire | Safety net for long-running sessions |
| Menu "Refresh Now" | User action | Manual override (bypasses idempotency) |

**Idempotency guard:** `updateWallpaper()` compares `(today, currentPhase)` against a stored `lastAppliedKey` in `UserDefaults`. If unchanged and the dated file exists on disk, it returns early without recompositing. The "Refresh Now" menu item bypasses the guard.

**Flow:**

```
updateWallpaper(force: Bool = false)
  → let phase = PhaseCalculator.phase(for: Date())
  → let key = "\(today)|\(phase.phaseName)"
  → if !force && key == lastAppliedKey && fileExistsForToday() { return }
  → let base = ImageProvider.baseImage(for: phase.phaseName)
  → let canvas = largestScreenPixelSize()
  → let composed = Compositor.composite(base:, phase:, canvasSize: canvas)
  → WallpaperSetter.apply(image: composed, for: today)
  → lastAppliedKey = key; publish state to MenuBarController
```

**Concurrency:** Single serial `DispatchQueue` (`com.lunar.updates`) funnels all triggers so concurrent wake events cannot race. UI updates are marshalled to `@MainActor`.

**Error handling:**
- Any exception inside `updateWallpaper` is logged to `~/Library/Logs/Lunar/lunar.log`. Menu-bar icon shows a small red dot; tooltip reveals the error message. Never crashes.
- Missing bundled image (shouldn't happen — it's part of the app bundle): log, skip, show error state. Next day's phase may differ and recover.

## 6. Menu-bar UI

SwiftUI `MenuBarExtra`. Icon: SF Symbol `moon.fill` — simple, always legible. No dynamic glyph; the wallpaper itself carries the signal.

Menu items:
- `Today: Waxing Gibbous · 87%` *(disabled label)*
- `Next phase: Full Moon · Apr 24` *(disabled label)*
- ─
- `Refresh Now`
- `Open Phases Folder…` (reveals override folder in Finder; creates it if absent)
- `Open Log`
- ─
- `Launch at Login` (toggle — `SMAppService.mainApp.register()` / `.unregister()`)
- ─
- `Quit Lunar`

## 7. Project layout

```
lunar/
├── Package.swift                 # SwiftPM, macOS(.v14) target
├── Sources/
│   └── Lunar/
│       ├── App.swift             # @main, MenuBarExtra scene
│       ├── AppCoordinator.swift
│       ├── MenuBarController.swift
│       ├── PhaseCalculator.swift
│       ├── ImageProvider.swift
│       ├── Compositor.swift
│       ├── WallpaperSetter.swift
│       ├── Logging.swift
│       └── Resources/
│           └── phases/           # 8 bundled PNG placeholders
├── Tests/
│   └── LunarTests/
│       ├── PhaseCalculatorTests.swift
│       ├── ImageProviderTests.swift
│       └── CompositorTests.swift
├── scripts/
│   ├── build.sh                  # swift build -c release → .app bundle
│   └── install.sh                # copies .app to ~/Applications
├── README.md
└── docs/
    └── superpowers/specs/
        └── 2026-04-21-lunar-design.md
```

## 8. Build & install

**Build (`scripts/build.sh`):**
1. `swift build -c release`
2. Assemble `Lunar.app/Contents/{MacOS,Resources,Info.plist,PkgInfo}` by hand. `Info.plist` declares `LSUIElement=true`, `CFBundleIdentifier=com.roman.lunar`, minimum system version 14.0.
3. Copy the release binary in; copy bundled phase PNGs to `Contents/Resources/phases/`.
4. `codesign -s - --force --deep Lunar.app` (ad-hoc signature).

No Xcode project file. CLI build keeps the repo clean and reproducible.

**Install (`scripts/install.sh`):**
1. Run `build.sh`.
2. Copy `Lunar.app` → `~/Applications/Lunar.app` (overwriting).
3. On first launch, the user toggles "Launch at Login" in the menu; `SMAppService.mainApp.register()` handles the rest — no manual plist required on modern macOS.

## 9. Logging

`Logging.swift` wraps `os.Logger` with category `com.lunar` plus a rolling file logger at `~/Library/Logs/Lunar/lunar.log` (1 MB cap, one rotation retained). The "Open Log" menu item opens the current file in Console.

## 10. Testing

| Module | Type | What |
|---|---|---|
| `PhaseCalculator` | Unit | 30+ fixed dates from NASA GSFC eclipse catalog (2020–2030). Assert phase name match and illumination within ±0.02 of published value. |
| `ImageProvider` | Unit | Temp directory. Override > bundle precedence. Missing override falls back. Malformed PNG handled. |
| `Compositor` | Snapshot | Render 3 phases at 2 canvas sizes. Compare PNG hashes. Regenerate via flag. |
| `WallpaperSetter` | Manual | `NSWorkspace` side effects can't be unit-tested. Covered by an end-to-end smoke-check script. |
| `AppCoordinator` | Unit | Inject fakes for all four modules. Verify idempotency guard, force-refresh path, error paths. |

Tests run via `swift test`. No CI required.

## 11. Non-goals (explicit)

- No automatic image generation. User supplies the 8 phase images (or uses bundled placeholders).
- No Southern Hemisphere support. Images are rendered Northern Hemisphere orientation only.
- No per-display wallpaper configuration. All screens get the same image.
- No Dynamic Desktop (`.heic`) authoring.
- No telemetry, no network activity, no updates. Personal app, local build.
- No multi-user / Family Sharing support. Single-user only.
- No App Store distribution. Non-sandboxed + ad-hoc sign.

## 12. Out of scope for v1 (possible future)

- User-selectable overlay content (hide date, change font, toggle illumination %).
- Configurable update time for the daily timer.
- HEIC Dynamic Desktop generation with embedded light/dark variants, which may (behavior via `setDesktopImageURL` is not definitively documented) eliminate the appearance-change re-apply mechanism.
- Per-display wallpaper toggles.
- Southern Hemisphere support.

## 13. Verified external facts (research summary)

- `NSWorkspace.setDesktopImageURL(_:for:options:)` remains the only public API for wallpaper-setting on macOS 14, 15, and 26; still functional with known caveats.
- Same-URL-different-contents refresh bug is real and reproducible (`sindresorhus/macos-wallpaper` issue #44). Dated filenames are the correct workaround.
- Setting a plain PNG updates only the currently active appearance slot; no public API exists to set both slots in one call. Dual-slot syncing requires observing appearance changes.
- `WallpaperAgent` and container storage on Sequoia/Tahoe have no public hooks. Direct plist manipulation is strongly discouraged by Apple DTS.
- Non-sandboxed + ad-hoc signing is sufficient for local personal use. Location (`/Applications` vs `~/Applications`) does not affect the API.

## 14. Open questions / flagged uncertainties

- Whether macOS Tahoe 26 writes through the new container cleanly in every edge case via `setDesktopImageURL`. Current public reports are positive but limited; integration testing on the target machine will confirm.
- Private-API techniques for dual-slot setting may exist but are undocumented and not used here.
