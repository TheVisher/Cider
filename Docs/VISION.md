# Cider Vision

> **Read this first.** This document explains what Cider is, what it isn't, and the principles that guide every design decision.

---

## What Cider Is

Cider is a **native macOS command palette** — a unified launcher for your windows and pinned apps that appears instantly with a double-tap of the Option key.

**The core insight:** Dock, Stage Manager, and Spotlight are three separate tools that should be one. Cider replaces all of them with a single, Raycast-style floating palette that's always a keystroke away.

---

## The Interface

### The Command Palette (Primary)

A floating acrylic panel that appears on-demand. This is Cider.

- **Pinned apps** — Your dock replacement (horizontal row with running indicators)
- **Window list** — Your Stage Manager replacement (grouped by monitor and app)
- **Search** — Filter windows and apps instantly
- **Window actions** — Close, minimize, move windows between monitors
- **Auto-hide apps** — Focus one app, others move aside

The palette never steals focus from your active app. Click a window, and you're there — the palette disappears, your work continues.

### Activation

- **Double-tap Option** — Toggle the palette (currently fixed to Option)
- **Click menu bar icon** — Alternative activation
- **Global search** — Start typing immediately to filter

### Future: Companion Features

Notes and bookmarks are represented as tabs in the palette today (coming soon). Dedicated companion windows may come later.

---

## Design Principles

### Raycast-Style Acrylic

Cider uses a dark, translucent acrylic material inspired by Raycast — not Apple's Liquid Glass. This provides:

- **Predictable appearance** — Looks the same on any desktop background
- **Clean aesthetic** — Dark, minimal, professional
- **No focus dependency** — Materials work even when the app isn't focused

Implementation: `NSVisualEffectView` with `.underWindowBackground` material and `.behindWindow` blending, plus dark overlays. See `ACRYLIC_STYLE.md` for details.

### Non-Activating Panels

The cardinal rule: **Cider never steals focus.**

The command palette uses `NSPanel` with `.nonactivatingPanel` style. Click it, use it, and your cursor is still in your document, your code still has focus, your game is still running.

### Native, Not Wrapped

Swift, SwiftUI, AppKit. No Electron, no web views, no cross-platform frameworks. Cider should feel like it shipped with macOS.

Use system APIs: `NSPanel` for floating windows, `AXUIElement` for window management, `CGWindowListCreate` for window enumeration.

### Instant Response

The palette must appear within 100ms of activation. No loading states, no spinners, no "warming up." The window list is continuously updated in the background so it's always ready.

### Context Over Destination

You don't "open Cider." You tap Option twice, see your windows, click one, and you're there. The palette is a momentary overlay that gets out of your way immediately.

---

## What Cider Is Not

- **Not Raycast/Alfred.** No workflows or plugins yet. Cider focuses on windows and a small pinned-apps row (dock replacement), not a full launcher.
- **Not Stage Manager.** No automatic grouping, no "stages." You control where windows go.
- **Not a sidebar.** The palette appears when you need it and disappears when you don't. It doesn't occupy permanent screen space.
- **Not a notes app.** Companion windows may come later, but the core product is window management.

---

## The Name

**Cider** works on multiple levels:

- Phonetically close to "sider" — it sits beside your work
- Made from apples — it's for macOS
- Refreshing and crisp — it cleans up your window chaos

The logo is an amber/gold S-shaped apple peel spiral.

---

## Product Positioning

Dock is always visible but shows apps, not windows.
Stage Manager groups windows automatically — often wrong.
Spotlight finds files but not your open windows.

**Cider is a command palette for everything on your screen.**

Double-tap. Click. Done. That's the pitch.
