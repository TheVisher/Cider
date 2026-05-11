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

## Feature Angles

Use this as the compact source of truth for social-facing feature wording. Check core docs before posting anything about testing or planned features.

| Feature / use case | Status | Safe wording | Avoid saying | Why it is interesting |
|---|---|---|---|---|
| Fast Mac capture | public beta | Cider is a native Mac app for quickly capturing bookmarks, notes, files, dates, contacts, screenshots, tags, and folders from a floating panel. | Do not imply every capture path is perfect or fully automated. | It explains the product in one concrete daily workflow. |
| Clipboard URL capture | public beta | Copy a URL and Cider can offer to save it, so links do not get stranded in tabs or chat threads. | Do not promise flawless duplicate prevention while cross-process bookmark capture is still being hardened. | It is specific, relatable, and already proven as a social angle. |
| Screen capture and OCR routing | public beta | Cider can turn useful text trapped in screenshots into saved context, with explicit routing into notes, dates, or contacts. | Do not imply OCR always extracts everything or routes without user visibility. | It shows Cider helping with messy real-world information. |
| Kanban work surface | public beta | Cider's Kanban keeps roadmap ideas, bugs, QA notes, follow-ups, and handoffs in cards instead of scattered Markdown plans. | Do not pitch it as a full project-management suite. | It connects the app feature to the way Cider itself is built. |
| Dashboard / Home command center | testing | Dashboard/Home is being shaped into a personal command center for current work, reminders, vault pulse, resurfacing, docs health, inbox health, and agent summaries. | Do not call it finished, broadly available, or a generic feed replacement. | It is the clearest second-brain direction beyond capture. |
| Shared agenda / briefing relevance | planned | Cider is working toward one relevance layer for Dashboard, CLI JSON, Telegram, and agent briefings, so reports explain why something matters today. | Do not claim daily brief behavior is already complete or universally accurate. | It turns reminders and dates into a useful social story about less noise. |
| Main Brain / Hermes chat | testing | Main Brain is being tested as Cider's native chat surface for the user's primary agent, wired toward Hermes session behavior while the vault stays durable memory. | Do not imply Hermes/Main Brain is in the public beta build unless core docs explicitly say so. | It hints at the AI direction without overpromising availability. |
| Local-first optional AI | public beta | Cider works as a local-first knowledge base without AI, and AI can support recall, synthesis, metadata, OCR, and organization when enabled. | Do not say AI replaces local truth or that every model/provider path is production-ready. | It reassures users who want utility without AI lock-in. |
| Bills, birthdays, and life logistics | do not mention yet | Internal direction only: Cider should eventually reduce repeated life-admin remembering. | Do not post examples like rent, bills, birthdays, anniversaries, or life assistant workflows as available features yet. | It is promising, but current docs frame it as product direction and hardening work. |

## Social Workflow

Active social drafts, approvals, published URLs, blockers, and handoffs belong on the Cider Social Kanban board:

```text
~/CiderVault/.cider/boards/c0ffee.yaml
```

Do not recreate `SOCIAL.md` for social queues or post history.

Bluesky automation should publish only approved cards from the Cider Social board. If no approved card exists, it should create a candidate in `Needs Approval` and stop.

For Bluesky automation runs, use the Codex in-app Browser plugin with the `iab` backend when available. Verify the account is `@ciderapp.bsky.social` before publishing.

Hermes, Main Brain, and AI angles must be checked against current core docs before posting. If a feature is still in testing, phrase it as testing, experimental, being wired up, or being worked on.
