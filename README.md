# DrawOver v0.6

A native macOS screen annotation app inspired by [Scribbble](https://www.scribbble.app/) — draw on top of any application with a hotkey-driven workflow, floating toolbar, and OS-level overlay capture compatible with Zoom, OBS, and screen sharing.

## Scribbble research summary

Scribbble is a Mac-first screen annotation tool (not to be confused with Dribbble). It targets presenters, streamers, teachers, and designers who need to mark up live content without leaving their current app.

### Core value proposition

| Aspect | Scribbble approach |
|--------|-------------------|
| **Interaction model** | Press hotkey → draw on screen → press again to clear |
| **Overlay** | OS-level drawing above all windows; captured by Zoom/OBS/Loom automatically |
| **Distribution** | Menu bar / accessory app (no Dock icon clutter) |
| **Pricing** | Free download, one-time license (no subscription) |
| **Platform** | macOS 11+, Apple Silicon native |

### Tool set (v0.6 parity target)

| Tool | Purpose |
|------|---------|
| **Pen** | Freehand strokes for redlines and callouts |
| **Highlighter** | Semi-transparent emphasis over text/UI |
| **Arrow** | Quick directional callouts |
| **Rectangle / Ellipse** | Shape framing, spacing boxes |
| **Text** | Inline notes on screen |
| **Spotlight** | Dim everything except a focus region |
| **Measure** | On-screen pixel distance for design QA |
| **Snapshot** | Capture full screen or region to clipboard |
| **Eraser** | Remove strokes (DrawOver addition) |

### UI patterns

1. **Floating toolbar** — narrow vertical strip with tool icons, color swatches, line width
2. **Docking** — toolbar snaps to left or right screen edge (not only free-floating)
3. **Visual language** — macOS-native materials (blur/vibrancy), SF Symbols, compact layout
4. **Status indicator** — clear on/off state for drawing mode
5. **Minimal chrome** — no main window; lives in menu bar

### What Scribbble deliberately omits

- Screen zoom (use macOS Accessibility zoom instead)
- Built-in screen recording
- Cursor highlight (Presentify’s differentiator)
- In-file persistence (annotations are ephemeral, screen-overlay only)

### Technical requirements to replicate

```
┌─────────────────────────────────────────────────────────┐
│  Menu Bar App (LSUIElement)                             │
│  ├── Global hotkeys (Carbon / CGEvent, Accessibility)   │
│  ├── Full-screen overlay windows (per NSScreen)         │
│  │   └── Transparent NSWindow @ screen-saver level      │
│  ├── Floating NSPanel toolbar (SwiftUI)                 │
│  ├── Core Graphics drawing canvas                       │
│  └── ScreenCaptureKit for snapshots                     │
└─────────────────────────────────────────────────────────┘
```

**Permissions required:**

- **Accessibility** — global hotkeys when other apps are focused
- **Screen Recording** — snapshot capture via ScreenCaptureKit

---

## DrawOver implementation

This repo implements the Scribbble-style workflow as a native Swift / SwiftUI + AppKit app.

### Architecture

```
DrawOver/
├── DrawOverApp.swift          # @main, settings, app delegate
├── Models/
│   ├── DrawingTool.swift      # Tool enum + shortcuts
│   ├── Annotation.swift       # Drawable primitives + CG rendering
│   └── AppState.swift         # Shared observable state
├── Views/
│   ├── DrawingCanvasView.swift  # NSView mouse handling + draw
│   ├── OverlayWindow.swift      # Per-screen borderless windows
│   └── ToolbarView.swift        # SwiftUI floating toolbar
└── Services/
    ├── HotkeyManager.swift      # Carbon global hotkeys
    ├── SnapshotService.swift    # ScreenCaptureKit capture
    └── MenuBarController.swift  # NSStatusItem + menu
```

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌃⌘D` | Toggle drawing mode |
| `⌃⌘C` | Clear all annotations |
| `⌘Z` | Undo |
| `⌃⌘S` | Snapshot to clipboard |
| `⌥1` – `⌥8` | Select tools (pen → measure) |

### Build & run

**Requirements:** Xcode 15+ (full Xcode, not only Command Line Tools), macOS 13+

```bash
cd DrawOver
open DrawOver.xcodeproj
# Product → Run (⌘R)
```

Or from terminal:

```bash
xcodebuild -project DrawOver.xcodeproj -scheme DrawOver -configuration Release build
open build/Release/DrawOver.app
```

On first launch:

1. Click the menu bar pencil icon (or press `⌃⌘D`) to enable drawing mode
2. Use the floating toolbar on the right to pick tools and colors
3. Draw over any app — annotations appear on the overlay layer
4. Press `⌃⌘C` to clear, or click the menu bar icon again to pause drawing

### Roadmap (beyond v0.6)

- [ ] Interactive region-select snapshot (marquee)
- [ ] Persist toolbar position across launches
- [ ] Multi-monitor coordinate normalization
- [ ] Cursor highlight mode (Presentify-style)
- [ ] Export annotated still to file
- [ ] App Store sandbox + notarization

## License

MIT — for learning and personal use. Scribbble is a separate commercial product; DrawOver is an independent open implementation inspired by its UX patterns.
