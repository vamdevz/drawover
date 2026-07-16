# DrawOver — Tools Reference

Step-by-step guide for every drawing tool in DrawOver. Use this when you want to know **what each tool does** and **exactly how to use it**.

For setup, permissions, and general workflows, see the [User Guide](USER_GUIDE.md).

---

## Before you draw

1. Click the **menu bar pencil** or press **⌥D** to enable DrawOver.
2. Click the **green dot** on the toolbar so it turns **green** (drawing mode on).
3. Pick a tool from the toolbar or with **⌥1** through **⌥7**.
4. Choose a **color** and adjust **stroke width** (`−` / `+`) when the tool supports it.

**Tip:** Annotations stay on screen when you switch tools (pen → rectangle → arrow, etc.). You can layer shapes, arrows, and freehand marks on top of each other.

---

## Tool 1 — Pen

**Shortcut:** ⌥1  
**Best for:** Freehand circles, underlines, handwritten notes, drawing on top of boxes and arrows.

### How to use

1. Select **Pen** on the toolbar (or press **⌥1**).
2. Adjust line thickness with **Stroke − / +** if needed.
3. **Click and drag** anywhere on the screen to draw.
4. Release the mouse to finish the stroke.

### Tips

- Draw **on top of** rectangles, ellipses, and arrows — existing shapes stay visible.
- Use **⌘Z** to undo a stroke, **⌘⇧Z** to redo.
- To **move** a shape instead of drawing over it, switch to the rectangle, ellipse, or arrow tool and drag the shape.

---

## Tool 2 — Highlighter

**Shortcut:** ⌥2  
**Best for:** Emphasizing text, paragraphs, or UI areas without fully hiding what's underneath.

### How to use

1. Select **Highlighter** (or press **⌥2**).
2. **Click and drag** over the area you want to highlight.
3. Release to finish.

### Tips

- Highlighter strokes are **wider** and **semi-transparent** by default.
- Like the pen, you can highlight **over existing shapes** without moving them.
- Adjust **Stroke − / +** for a thicker or thinner highlight band.

---

## Tool 3 — Arrow

**Shortcut:** ⌥3  
**Best for:** Pointing at a button, icon, or detail on screen.

### How to use

1. Select **Arrow** (or press **⌥3**).
2. **Click and drag** from the tail to the arrow tip.
3. Release to place the arrow.

### Add a caption (label)

1. Keep **Arrow** selected.
2. **Double-click** the arrow line.
3. Type your label and press **Return** (or click outside to commit).

### Move an arrow or its caption

1. With **Arrow** selected, **click and drag** the arrow line to reposition it.
2. **Click and drag** the caption text to move the label.

### Tips

- Use **⌥-click** while on rectangle/ellipse tools to delete an arrow (see Rectangle tool).
- **⌘Z** / **⌘⇧Z** undo and redo arrow changes.

---

## Tool 4 — Rectangle

**Shortcut:** ⌥4  
**Best for:** Framing UI elements, bugs, regions, or steps in a flow.

### How to use (basic box)

1. Select **Rectangle** (or press **⌥4**).
2. **Click and drag** diagonally to size the box.
3. Release to finish.

### Add a caption under the box

1. Keep **Rectangle** selected.
2. **Double-click** inside or on the box edge.
3. Type your caption and press **Return**.

### Draw an arrow while on the rectangle tool

Hold **⌃ (Control)** and drag — this draws an **arrow** instead of a box.

| Gesture | Result |
|---------|--------|
| **Drag** | Rectangle |
| **⌃ + drag** | Arrow |
| **⌃ + drag starting on an existing box** | Callout arrow from the **nearest edge** of that box to your cursor |

### Callout arrow from a box (leader line)

1. Draw a rectangle first.
2. Keep **Rectangle** selected.
3. Hold **⌃** and drag **from inside or on the box** outward.
4. The arrow starts at the box border and points to where you release.

### Move a box or caption

1. With **Rectangle** (or **Ellipse**) selected, **click and drag** the box to move it.
2. **Click and drag** a caption to reposition the text.
3. Captions near the box move together when you drag the box.

### Delete a box, arrow, or nearby caption

1. With **Rectangle** or **Ellipse** selected, hold **⌥ (Option)** and **click** the item to remove.

### Tips

- After drawing a box, switch to **Pen** (**⌥1**) to scribble notes inside the frame.
- Toggle **Auto-caption every new box** (speech-bubble icon on the toolbar when rectangle/ellipse is active) in Settings or the toolbar if you want captions to open automatically after each new shape.

---

## Tool 5 — Ellipse

**Shortcut:** ⌥5  
**Best for:** Circling avatars, round buttons, or soft emphasis areas.

### How to use

1. Select **Ellipse** (or press **⌥5**).
2. **Click and drag** to size the oval.
3. Release to finish.

### Everything else

Ellipse supports the **same gestures as Rectangle**:

- **Double-click** → caption below the shape  
- **⌃ + drag** → arrow or callout from an existing oval  
- **Click and drag** → move the oval (and nearby captions)  
- **⌥ + click** → delete  
- Switch to **Pen** to draw inside the oval  

---

## Tool 6 — Text

**Shortcut:** ⌥6  
**Best for:** Standalone labels anywhere on screen (not tied to a shape).

### How to use

1. Select **Text** (or press **⌥6**).
2. **Click** where you want the label.
3. Type in the field that appears.
4. Press **Return** or click outside to commit.

### Move existing text

1. With **Text** selected, **click and drag** an existing label to reposition it.

### Tips

- Only **one text field** is open at a time.
- To label a box or arrow, you can also **double-click** the shape with the rectangle/ellipse/arrow tool — that places a caption tied to the shape.

---

## Tool 7 — Eraser

**Shortcut:** ⌥7  
**Best for:** Removing pen strokes, highlighter marks, and other annotations you drag over.

### How to use

1. Select **Eraser** (or press **⌥7**).
2. **Click and drag** over marks you want to remove.
3. Strokes and shapes under the eraser path are deleted as you drag.

### Tips

- Eraser size follows the current **stroke width** setting.
- Use **⌘Z** if you erase too much.

---

## Toolbar actions (not tools, but used constantly)

| Control | What it does |
|---------|----------------|
| **Green dot / pencil** | Drawing mode on (green) or off (annotations hidden) |
| **Stroke − / +** | Thinner or thicker lines (pen, highlighter, arrow, shapes) |
| **Color dots** | Pick stroke color |
| **Undo** (↩) | Undo last action — **⌘Z** |
| **Redo** (↪) | Redo — **⌘⇧Z** |
| **Trash** | Clear all annotations — **⌥C** |
| **Camera** | Snapshot active monitor to clipboard — **⌘S** |
| **Dock arrows** | Pin toolbar to left or right screen edge |

---

## Keyboard shortcuts (defaults)

| Shortcut | Action |
|----------|--------|
| **⌥D** | Toggle drawing on/off |
| **Esc** | Clear all annotations (stay in drawing mode) |
| **Esc Esc** (quickly) | Turn drawing off (green dot off) |
| **⌥C** | Clear all |
| **⌘Z** | Undo |
| **⌘⇧Z** | Redo |
| **⌘S** | Snapshot to clipboard |
| **⌥1** – **⌥7** | Pen → Eraser |

Customize in **menu bar → Settings → Shortcuts**.

---

## Quick workflow examples

### Frame a bug and annotate it

1. **⌥4** → drag a **rectangle** around the issue.  
2. **Double-click** the box → type a caption.  
3. **⌥1** → **pen** → circle the exact broken pixel or button.  
4. **⌘S** → snapshot → paste into Slack or Jira.

### Point from a label to a detail

1. **⌥4** → draw a box around a UI element.  
2. **⌃ + drag** from the box edge to the detail (callout arrow).  
3. **Double-click** the box to add a caption.

### Present live, then clean up

1. **⌥D** → green dot on → draw with pen/highlighter/arrows.  
2. **Esc** once → clear annotations, stay ready to draw again.  
3. **Esc Esc** → exit drawing mode entirely.

---

## Related docs

- [User Guide](USER_GUIDE.md) — setup, settings, troubleshooting, screen sharing  
- [README](../README.md) — download, build, and repository overview
