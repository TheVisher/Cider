# Cider Social Plan

This is the working hub for Cider's public channels, launch notes, post ideas, and voice. Keep it useful, not precious.

## Current Channels

| Channel | Status | Link | Purpose |
| --- | --- | --- | --- |
| Website | Live | https://cider.so | Primary home for the beta, download link, and social links. |
| GitHub | Live | https://github.com/TheVisher/Cider | Source, releases, issues, feedback, and public project credibility. |
| Discord | Live | https://discord.gg/TzErWTgm4d | Community discussion, beta tester feedback, ideas, bugs, and general chat. |
| Bluesky | Live | https://bsky.app/profile/ciderapp.bsky.social | Lightweight public updates, launch posts, build notes, and beta calls. |
| Reddit | Live | https://www.reddit.com/r/CiderApp/ | Official subreddit for Cider beta feedback, bug reports, feature ideas, and support. |

## Published Posts

### Reddit

- 2026-04-27: Welcome post
  - URL: https://www.reddit.com/r/CiderApp/comments/1sx1fgp/welcome_to_rciderapp/
  - Copy:

```text
Hey, welcome to the official Cider Subreddit.

Cider is a native macOS app for catching the stuff your brain swears it will remember: links, notes, dates, contacts, ideas, and other small bits that usually end up scattered across tabs and good intentions.

This subreddit is for:
- Beta feedback
- Bug reports
- Feature ideas
- Questions
- Weird workflows Cider should probably handle better

Useful links:
- Website: https://cider.so
- Beta download: https://github.com/TheVisher/Cider/releases/latest
- GitHub: https://github.com/TheVisher/Cider
- Discord: https://discord.gg/TzErWTgm4d
- Bluesky: https://bsky.app/profile/ciderapp.bsky.social

If you find something broken, tell me what happened, what you expected, and whether Cider was being clever or merely dramatic.

Thanks for checking it out. This is early beta, which is a polite way of saying: it works, but it would love a few more real humans poking at it.
```

### Bluesky

- 2026-05-06: Clipboard URL capture spotlight
  - URL: https://bsky.app/profile/ciderapp.bsky.social/post/3ml7ppqgfuc2y
  - Copy:

```text
Copy a URL, and Cider offers to save it.
No “I’ll paste it somewhere later” lies required.

Double-tap Option, hit Save, keep moving.

https://cider.so
```

- 2026-05-05: Small capture positioning post
  - URL: https://bsky.app/profile/ciderapp.bsky.social/post/3ml5642rgz226
  - Copy:

```text
Cider is for the stuff that is too small for a full notes app but too important to trust to your brain.

Bookmarks. Notes. Dates. Contacts. Ideas.

Hit Option twice, capture it, move on with your life like a civilized person.

https://cider.so
```

- 2026-04-26: First beta post
  - URL: https://bsky.app/profile/ciderapp.bsky.social/post/3mkgpivexd22r
  - Copy:

```text
Cider is now in beta.

It’s a native macOS app for catching the little stuff your brain swears it will remember: links, notes, dates, contacts, ideas, all from a quick Option double-tap.

Tiny app, fewer tabs, less digital soup.

Try it: https://cider.so
```

## Voice

Cider should sound like a useful product made by a real person, not a startup press release.

Use:

- Clear explanations of what Cider does.
- Light humor and occasional snark.
- Specific examples: links, notes, dates, contacts, ideas, beta feedback.
- Short posts that feel human.
- Plain CTAs: try it, report bugs, share ideas, join Discord.

Avoid:

- Corporate launch-speak.
- "Revolutionize your workflow" energy.
- Over-polished AI phrasing.
- Hype without showing what the app actually does.
- Em dashes in social copy.

## Product One-Liner

Cider is a native macOS app for quickly capturing the little things you do not want to lose: bookmarks, notes, dates, contacts, ideas, and whatever else your brain was absolutely going to forget five minutes from now.

Shorter version:

Cider is a native macOS app for quickly capturing bookmarks, notes, dates, contacts, and ideas from a quick Option double-tap.

## Beta CTA

Default CTA:

```text
Try the beta: https://cider.so
```

Feedback CTA:

```text
Found a bug, have an idea, or just want to tell me something feels weird? Join the Discord: https://discord.gg/TzErWTgm4d
```

GitHub CTA:

```text
Issues and releases are on GitHub: https://github.com/TheVisher/Cider
```

## Posting Cadence

For pre-beta and early beta, keep it light:

- Bluesky: 2-3 posts per week.
- Discord: only meaningful updates, bug notes, and discussion prompts.
- GitHub: releases, issues, and changelog-like updates.
- Reddit: occasional thoughtful posts once ready, not drive-by self-promo.

## Posting Mechanism

For Bluesky automation runs, use the Codex in-app Browser plugin (`@Browser`, `browser-use@openai-bundled`) with the `iab` backend. The in-app browser is logged into `@ciderapp.bsky.social` and can publish directly.

Do not try to use Dia, Safari, or another desktop browser first. If the Browser plugin is unavailable, record that blocker in this file and leave the queue item unposted.

## Weekly Social Checklist

Use this as the weekly visual pass. The goal is consistency without turning Cider into a content treadmill.

```text
Week of: __________

Build / GitHub
[ ] Pick this week's product focus
[ ] Commit meaningful work as it lands
[ ] Push to main only when stable
[ ] Decide if this week needs a beta release
[ ] If releasing, create/update GitHub release notes

Discord
[ ] Check #bugs for anything urgent
[ ] Check #ideas and #beta-feedback for patterns
[ ] Post one useful update only if there is something users should know

Bluesky
[ ] Post one casual build/product update
[ ] Post one beta/feedback/release update if there is news
[ ] Reply to any real mentions or questions

Reddit
[ ] Check r/CiderApp for comments or spam
[ ] Post at most one thoughtful thread if there is a real topic
[ ] Avoid link-heavy posts unless necessary

Maintenance
[ ] Add any published posts to this file
[ ] Note anything users asked for repeatedly
[ ] Decide the next small social task
```

Minimum viable week:

```text
[ ] Ship or improve something
[ ] Check Discord
[ ] Post once on Bluesky
[ ] Check Reddit
```

If the week is busy, do only the minimum viable week. The app matters more than feeding the social machines.

## Release-Day Checklist

Use this when a beta build goes out.

```text
Release: __________
Date: __________

Before posting
[ ] Build passes
[ ] App opens and core capture flow works
[ ] GitHub release exists
[ ] Download link works
[ ] Known issues are written down

GitHub
[ ] Tag/release published
[ ] Release notes include changes, fixes, and known issues

Discord
[ ] Post short announcement in announcements
[ ] Mention the download link
[ ] Ask for feedback in the right channel

Bluesky
[ ] Post short public update
[ ] Mention one user-facing change
[ ] Link to cider.so or the release, not both unless needed

Reddit
[ ] Only post if the release is meaningful
[ ] Prefer a short r/CiderApp thread over outside subreddit posts
[ ] Keep links minimal

After posting
[ ] Add post URLs and copy to Published Posts
[ ] Watch for bug reports for 24 hours
```

## When To Post

Post when one of these happened:

- New beta release.
- Noticeable feature added.
- Bug fix users may care about.
- Known issue users should avoid.
- Specific feedback request.
- Useful milestone.
- Clear explanation of what Cider does.

Skip posting when:

- It is just a tiny internal refactor.
- The update needs three paragraphs of caveats.
- The only CTA is "please look at my app."
- You are posting because the checklist exists, not because there is something useful to say.

## Brand Assets

Current visual direction:

- Warm dark gradient background.
- Abstract amber loop mark.
- Keep layouts calm and sparse.
- Prefer platform-specific crops over forcing one banner everywhere.
- Avoid tiny text, crowded taglines, and anything that looks like generic gradient wallpaper.

Current assets:

```text
Primary abstract mark: brand/assets/logo-winner-triangular-loop-isolated-softclean.png
GitHub README banner: brand/assets/readme-banner-v2.png
Reddit banner: brand/assets/social-banner-reddit-v3.png
Bluesky banner: brand/assets/social-banner-bluesky-mark-v3-right.png
Discord banner candidate: brand/assets/social-banner-discord-mark-v2-right.png
```

Platform notes:

- GitHub README uses `brand/assets/readme-banner-v2.png`.
- Reddit uses the Reddit-specific banner with the faint oversized mark on the left.
- Bluesky uses the right-side faint mark so the avatar does not cover the main visual.
- Discord currently only exposes preset color banners for the server profile. The image banner candidate is saved for later if custom server banners become available.

## Content Buckets

Rotate through these so the feed does not become one long "please try my app" sign:

- What Cider does.
- Small feature demos.
- Build-in-public updates.
- Beta feedback requests.
- Release notes and changelog posts.
- Tiny jokes about digital clutter.
- Founder notes: why this exists, what problem it solves, what changed this week.

## Feature Angles

Use this as the social-safe feature inventory. Keep statuses honest and avoid implying anything is shipped unless it is in the public beta build.

| Feature / use case | Status | Safe wording | Unsafe wording / overpromises to avoid | Why it’s interesting socially |
| --- | --- | --- | --- | --- |
| Instant capture panel (Option double-tap) | public beta | “Double-tap Option to pop Cider up anywhere, capture the thing, then disappear again.” | “Replaces your notes app.” “You’ll never forget anything again.” | Easy to demo. It’s a behavior change, not a giant workflow. |
| Bookmarks that feel like “library cards” (title + thumbnail + metadata) | public beta | “Save a tab in one keystroke. Cider keeps the thumbnail and context so it’s not just a dead URL.” | “Perfect web archive.” “Reads every site flawlessly.” | Everyone has a graveyard of bookmarks; this shows a clear upgrade. |
| Clipboard URL capture (Cider notices copied links) | public beta | “Copy a URL — Cider offers to save it.” | “Captures everything you copy (always).” | Small, delightful, and relatable: the ‘I’ll paste it later’ lie. |
| Screen capture → OCR → routed capture | public beta | “Grab part of your screen, OCR it, and route it into a note / date / contact.” | “100% accurate OCR.” “Understands any screenshot perfectly.” | Feels like magic, but the demo is concrete. |
| Local-first AI enrichment (auto-tags, OCR indexing, similar items, summaries) | public beta | “Optional local intelligence: auto-tags, OCR text, ‘find similar’, short summaries.” | “AI organizes your life automatically.” “Cloud brain.” | “AI, but not SaaS” is a strong differentiator if phrased carefully. |
| AI assistant chat (Apple Intelligence or optional local model) | public beta | “Optional assistant that can search your vault and take actions. No API keys required.” | “Always-on agent.” “Knows everything about you.” “Works on any Mac.” | Clear contrast with cloud-key workflows; good for nerdy build notes. |
| Folders + tags + saved views (tabs) | public beta | “Organize with folders and tags, plus tabs that remember your filters/layout.” | “Automatically perfect organization.” | Screenshots look good; it’s pragmatic and non-hypey. |
| Search palette + Spotlight indexing | public beta | “Cmd+K in-app search, plus Spotlight indexing so your vault shows up in macOS search.” | “Search reads your mind.” | Mac-native credibility; easy ‘built for macOS’ proof. |
| Todos, dates, reminders (with notifications) | public beta | “Todos and date cards, with reminders that can notify you.” | “Full calendar replacement.” “Full Reminders replacement.” | Turns capture into action; useful to show ‘not just bookmarks’. |
| Kanban boards inside Cider (parent/child cards + queued workflow) | testing | “We’re testing a built-in Kanban surface so ‘work’ doesn’t live in 12 random docs.” | “Kanban is fully shipped.” “Project management suite.” | Great for ‘how I build the app while building the app’ posts. |
| Dashboard as a second-brain feed (resurfacing + curation) | testing | “Exploring a calm dashboard that resurfaces your own context instead of being a generic feed.” | “Personalized news feed.” “Replaces your RSS/social feeds.” | Opinionated take on feeds; invites thoughtful feedback. |
| Hermes / Main Brain (second-brain chat parity work) | testing | “Testing a Hermes-powered ‘Main Brain’ chat surface inside Cider. Not public beta yet.” | “Main Brain is available now.” “Talk to Cider from anywhere (for everyone).” | High curiosity, but needs strict wording to avoid overpromising availability. |
| Cider Web companion | testing | “Cider Web exists, but it’s still in testing.” | “Web app is fully ready / stable.” | Good lightweight update for people who ask “is there a web version?”. |

## Post Backlog

## Planned / Upcoming

### Bluesky Planned Queue

- Clipboard URL capture spotlight (created: '2026-05-06') - posted
  - Status: posted (2026-05-06)
  - URL: https://bsky.app/profile/ciderapp.bsky.social/post/3ml7ppqgfuc2y
  - Copy:

```text
Copy a URL, and Cider offers to save it.
No “I’ll paste it somewhere later” lies required.

Double-tap Option, hit Save, keep moving.

https://cider.so
```

### Bluesky Drafts

```text
I built Cider because my "I'll remember that later" system was apparently just vibes and browser tabs.

It is a small native macOS app for capturing links, notes, dates, contacts, and ideas before they vanish into the fog.

Beta: https://cider.so
```

```text
Cider is for the stuff that is too small for a full notes app but too important to trust to your brain.

Bookmarks. Notes. Dates. Contacts. Ideas.

Hit Option twice, capture it, move on with your life like a civilized person.

https://cider.so
```

```text
Beta testers wanted for Cider.

Requirements:
1. Use a Mac.
2. Forget things sometimes.
3. Be willing to tell me when something is busted.

That is basically the whole onboarding funnel.

https://cider.so
```

```text
Small Cider update:

I am using the Discord as the main beta feedback spot for now. Ideas, bugs, sharp opinions, weird edge cases, all welcome.

Join here: https://discord.gg/TzErWTgm4d
```

```text
Cider is open on GitHub, partly because transparency is good and partly because bugs are easier to find when more than one person can stare at them angrily.

https://github.com/TheVisher/Cider
```

## Reddit Notes

Official account: https://www.reddit.com/user/Ciderapp/

Official subreddit: https://www.reddit.com/r/CiderApp/

Reddit posts should be written for the specific community, not copied from Bluesky.

Possible angles:

- "I built a small macOS capture app because my bookmarks/notes/date reminders were scattered everywhere."
- "Looking for beta feedback from Mac users who capture a lot of links and notes."
- "Open-source-ish/project feedback angle" for developer-friendly communities.

Avoid:

- Posting the same thing everywhere.
- Sounding like an ad.
- Ignoring subreddit rules.
- Dropping a link without context.

## Maintenance

When a new public post goes out, add it to `Published Posts` with the date, URL, platform, and copy. When a channel changes, update `Current Channels`.
