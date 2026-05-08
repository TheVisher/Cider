# Cider Brand Guide v1

## Brand Personality
Native - Clean - Focused - Premium - Calm

Cider is a lightweight macOS utility that feels built-in, not bolted on.
It prioritizes clarity, speed, and restraint over decoration.

---

## Icon

Concept:
Apple peel forming a subtle "C" as a continuous ribbon.

Rules:
- Continuous ribbon form
- Subtle depth only at top curl
- No visible seams
- No harsh shading splits
- No heavy gloss or chrome
- No cartoon fruit interpretation

Lighting:
Single soft light source from top-left.
Gradient must follow curvature of ribbon.
No vertical gradient seams.

---

## Color System

### Primary Peel Gradient
Top highlight: #F4A42B
Mid tone:      #D97706
Deep amber:    #B45309

Gradient must follow ribbon arc.

---

### Dark Surfaces
Primary Dark:  #0F1115
Panel:         #1C1F24
Muted Surface: #2A2D33

Never use pure black.

---

### Accent Glow (Marketing Only)
Amber glow at 12-18% opacity.
Soft blur only.
Not used in product UI.

---

## Typography

Wordmark:
SF Pro Display
Semibold
"Cider" (capital C only)

No gradient text.
Solid fill only.

On dark backgrounds:
#F4A42B or #EAEAEA

On light backgrounds:
#111111

---

## Asset Specifications

### Social Preview (GitHub OG Image)
- 1280x640
- Dark gradient background
- Centered icon
- Wordmark below
- Soft amber glow

### README Banner
- 1600x400
- Left: Icon
- Right: "Cider" wordmark + tagline
- Tagline: "Double-tap Option. Capture. Organize. Done."

### Favicon Set
- 32x32 and 16x16
- Simplified peel, increased contrast

### App Store Style Mock (Future)
- Mac window floating on dark gradient
- Icon in corner
- Minimal

---

## Social Voice

Cider social posts should sound like a useful Mac app made by a real person.

Use:
- Clear examples of what Cider does: bookmarks, notes, dates, contacts, ideas, files, screenshots, tags, folders, saved views, and quick capture.
- Light humor or mild snark when it fits.
- Short, specific copy with a plain CTA.
- `https://cider.so` as the default CTA.

Avoid:
- Corporate launch-speak.
- Vague productivity claims.
- Over-polished AI phrasing.
- Feature overpromises.
- Em dashes.

## Social Workflow

Active social drafts, approvals, published URLs, blockers, and handoffs belong on the Cider Social Kanban board:

```text
~/CiderVault/.cider/boards/c0ffee.yaml
```

Do not recreate `SOCIAL.md` for social queues or post history.

Bluesky automation should publish only approved cards from the Cider Social board. If no approved card exists, it should create a candidate in `Needs Approval` and stop.

For Bluesky automation runs, use the Codex in-app Browser plugin with the `iab` backend when available. Verify the account is `@ciderapp.bsky.social` before publishing.

Hermes, Main Brain, and AI angles must be checked against current core docs before posting. If a feature is still in testing, phrase it as testing, experimental, being wired up, or being worked on.
