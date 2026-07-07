# DrawOver

Native macOS screen annotation app — draw on top of any application with a floating toolbar, global hotkeys, and overlay capture compatible with Zoom, OBS, and screen sharing.

Inspired by tools like [Scribbble](https://www.scribbble.app/), DrawOver is an independent open-source implementation built with Swift, SwiftUI, and AppKit.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

**New here?** Read the **[User Guide](docs/USER_GUIDE.md)** — what DrawOver is, toolbar overview, and how to use every tool (including rectangle callouts and arrows).

## Features

- **Pen, highlighter, arrow, rectangle, ellipse, text, eraser**
- **Rectangle callouts** — drag a box, optional auto-caption below the shape, ⌃-drag for arrows
- **Floating toolbar** — dock left/right, adjustable opacity
- **Global hotkeys** — draw from any app (Accessibility permission required)
- **Multi-monitor overlays** — per-screen annotation layers
- **Snapshot to clipboard** — captures the active monitor with annotations composited
- **Menu bar app** — no Dock icon clutter (`LSUIElement`)

## Quick start (download & run)

No Xcode required if you only want to run the app.

### 1. Download

**Option A — Clone this repository**

```bash
git clone https://github.com/vamdevz/drawover.git
cd drawover
```

**Option B — Download ZIP from GitHub**

1. Open [github.com/vamdevz/drawover](https://github.com/vamdevz/drawover)
2. Click **Code → Download ZIP**
3. Extract the archive (double-click `drawover-main.zip` in Finder)

### 2. Extract the pre-built app (if using the zip inside `dist/`)

```bash
cd drawover/dist
unzip DrawOver-macOS.zip
```

Or in Finder: double-click `dist/DrawOver-macOS.zip`, then drag `DrawOver.app` to **Applications**.

### 3. Run

```bash
open dist/DrawOver.app
```

On first launch macOS may block the unsigned build:

1. **System Settings → Privacy & Security**
2. Click **Open Anyway** next to the DrawOver message  
   — or right-click `DrawOver.app` → **Open** → **Open**

### 4. Permissions

Grant when prompted:

| Permission | Why |
|------------|-----|
| **Accessibility** | Global hotkeys while other apps are focused |
| **Screen Recording** | Snapshot capture via ScreenCaptureKit |

### 5. Use

1. Click the **pencil icon** in the menu bar (or press **⌥D**) to start drawing
2. Use the floating toolbar to pick tools and colors
3. Click the **green dot** again to stop — annotations clear from the screen
4. Press **⌥C** to clear all, **⌘⇧S** snapshot (defaults may vary — see Settings → Shortcuts)

## Build from source

**Requirements:** Xcode 15+, macOS 13+

```bash
git clone https://github.com/vamdevz/drawover.git
cd drawover
open DrawOver.xcodeproj
# Product → Run (⌘R)
```

Or from Terminal:

```bash
./build.sh
open build/Build/Products/Debug/DrawOver.app
```

Release build:

```bash
xcodebuild -project DrawOver.xcodeproj -scheme DrawOver -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
open build/Build/Products/Release/DrawOver.app
```

## Repository layout

```
drawover/
├── docs/
│   ├── USER_GUIDE.md         # End-user guide (tools, shortcuts, workflows)
│   └── images/toolbar.png    # Toolbar screenshot
├── DrawOver/                 # Swift source code
│   ├── Models/               # AppState, annotations, tools, shortcuts
│   ├── Views/                # Canvas, overlay windows, toolbar
│   └── Services/             # Hotkeys, snapshots, menu bar
├── DrawOver.xcodeproj/       # Xcode project
├── dist/
│   ├── DrawOver.app          # Pre-built Release binary (macOS)
│   └── DrawOver-macOS.zip    # Same app, zipped for download
├── build.sh                  # Local debug build script
├── LICENSE                   # MIT
└── README.md
```

## Keyboard shortcuts (defaults)

| Shortcut | Action |
|----------|--------|
| `⌥D` | Toggle drawing mode |
| `Esc` | Stop drawing / dismiss caption |
| `⌥C` | Clear all annotations |
| `⌘Z` | Undo |
| `⌘S` | Snapshot to clipboard |
| `⌥1` – `⌥7` | Select tools |

Customize in **Settings → Shortcuts** (menu bar → Settings).

## Rectangle tool tips

| Gesture | Action |
|---------|--------|
| Drag | Draw rectangle |
| ⌃-drag | Draw arrow |
| ⇧-drag | Open caption after drawing |
| Double-click box | Add caption below the box |
| ⌥-click | Delete box / arrow / caption |

## Architecture

```
Menu Bar App (LSUIElement)
├── Global hotkeys (Carbon, Accessibility)
├── Full-screen overlay windows (per NSScreen, screen-saver level)
├── Floating NSPanel toolbar (SwiftUI)
├── Core Graphics drawing canvas
└── ScreenCaptureKit snapshots
```

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/vamdevz/drawover).

1. Fork the repo
2. Create a feature branch
3. Open a PR with a clear description and test notes

## Roadmap

- [ ] Marquee region snapshot
- [ ] Persist toolbar position across launches
- [ ] Code signing / notarization for easier first launch
- [ ] Export annotated still to file

## License

MIT — see [LICENSE](LICENSE).

DrawOver is not affiliated with Scribbble or any commercial screen-annotation product.
