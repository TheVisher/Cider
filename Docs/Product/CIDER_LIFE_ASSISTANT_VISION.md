# Cider Life Assistant Vision

## Core Vision

Cider should become the user's local-first life hub: a one-stop personal knowledge base, daily briefing surface, reminder system, media library, assistant-operated life wiki, and eventually the single app the user can rely on for everyday personal memory and organization.

Hermes/Cider should improve through real usage. Every time the assistant captures, routes, recalls, or struggles with something, that workflow should teach Cider how to become a better life assistant. When the assistant has to fall back to an external app, manual workaround, or non-Cider workflow, that gap should be documented as product debt so Cider can eventually absorb it.

## Capability Gap Capture Loop

A core operating rule for Hermes/Cider: if the user asks for a life-assistant action and Cider cannot do it natively yet, use the best macOS-native fallback when available instead of failing outright. Do not treat the external workaround as the final answer. Use the workaround to help the user now, then record the missing Cider capability as future product work.

Examples of gaps to capture:

- “remind me when I get home” requires location-aware reminders/geofencing
- reminders currently may use Apple Reminders as the preferred macOS-native fallback until Cider owns reminders
- calendar/contact/todo actions may use native macOS apps until Cider owns the model
- mobile push/voice/location features may require a future Cider mobile companion or relay
- agent delivery may require Telegram/iMessage until Cider has native notification routing

For each gap, document:

- user-facing request
- what Cider can do today
- what memory/recall failure the user is trying to prevent
- workaround used, if any
- desired native Cider behavior
- likely model/UI/CLI/API additions needed

This keeps Cider moving toward the user's goal: one trusted local-first app for memory, reminders, notes, bookmarks, media, tasks, and agent-assisted daily life.

## Dashboard + Text Briefing Relationship

Cider already has a Dashboard. The Dashboard should be treated as the **visual daily briefing** inside the app.

The assistant-generated text briefing and the in-app Dashboard should be related views over the same underlying life context:

- **Text briefing:** sent remotely through Telegram/voice/chat, useful when away from the Mac.
- **Visual Dashboard:** rich in-app surface for the same day/life context.

They should not become separate products or separate logic paths. The same underlying briefing engine should feed both:

- quick-capture notes, ideas, todos, events, and reminders that need resurfacing
- calendar/events
- reminders
- todos
- overdue/stale tasks
- pending approvals
- recent captures
- Inbox items needing triage
- important notes/bookmarks resurfaced at the right time
- contacts/follow-ups
- project status
- media/watchlist suggestions
- RSS/news/personalized reading briefings

## Learning User Organization

When the user gives the assistant bookmarks, links, notes, files, restaurants, media, or ideas, Cider should gradually learn how the user organizes things.

The assistant should:

- save conservatively at first
- ask when under roughly 90% confident
- route high-confidence items to the right folders
- remember user corrections
- update routing rules and workflows based on repeated decisions
- avoid guessing when metadata is weak

Over time, Cider should build an increasingly accurate personal routing model from the user's actual organization habits.

## Personal Libraries

Cider should support libraries of things the user cares about, such as:

- movies
- TV shows
- books
- games
- restaurants
- tools/apps
- articles
- creators
- products
- places/trip ideas

These libraries should not just be static folders. They should become queryable and assistant-aware.

Examples:

- “What movies did I save recently?”
- “What horror movies am I interested in?”
- “What TV shows did I want to watch?”
- “What restaurants did I save near Renton?”
- “What books have I mentioned but not read?”

## ADHD / Memory Support Companion

A major part of the product vision is that Cider should compensate for the user's ADHD and poor recall by quietly remembering open loops, interests, and follow-ups that the user would otherwise forget. Cider should act as the user's practical “second brain” — a local-first system that fills in the gaps of the user's real memory.

The core loop should be:

1. capture quickly with minimal friction: notes, ideas, todos, events, links, contacts, places, media, screenshots, voice thoughts, and reminders
2. understand enough context to store the item safely and connect it to related vault knowledge
3. recall/resurface the item later at the right time, date, place, device context, project context, or conversational trigger
4. let the user mark done/snooze/update/link/reroute without turning memory management into homework

Cider should not merely store things. It should help the user remember them when they become relevant again.

Cider should act like a dream companion for leisure and personal interests, not just productivity:

- remember shows the user is watching
- remember movies, books, and games the user saved or started
- ask whether the user watched/read/played something
- mark items as watched/read/finished/played
- track seasons, sequels, DLC, releases, and follow-ups
- remind the user when a new season airs or becomes available
- suggest similar shows, movies, books, or games based on the user's actual taste
- surface forgotten watchlists/backlogs at the right time
- help the user build a profile of what they like to do and why

The tone should be supportive and lightweight. The assistant should help the user remember and rediscover things, without making the system feel like homework.

## Contextual / Location-Aware Reminders

Cider should eventually own reminders directly instead of defaulting to Apple Reminders or other external apps. Real user need: “Remind me to check out Open WebUI when I get home.” Cider should understand this as a local-first, context-aware reminder tied to the user's life context and vault, not just a generic OS reminder.

Potential reminder triggers:

- location/geofence: home, work, saved places, restaurants, stores
- time/date: tonight, tomorrow, next weekend
- device/context: when the Mac is active, when the user returns home, when a workspace opens
- vault context: when viewing a related bookmark/project/note
- recurring follow-up: check later, ask again, new season/release reminders

Design principle: Cider can integrate with Apple Reminders/Calendar when useful, but should not be dependent on them as the primary product experience. The Cider Dashboard, Telegram/text assistant, and future mobile client should all surface the same Cider-owned reminders.

Implementation implication: Cider needs a first-class reminders/todos model with trigger metadata, source item links, completion state, notification delivery, and safe assistant creation/update flows.

## Media Taste and Ratings

The assistant should eventually help the user build taste profiles.

For movies/TV/books/games, the assistant could ask follow-up questions such as:

- “Did you watch this?”
- “Did you finish the season?”
- “What episode or season are you on?”
- “What rating would you give it?”
- “Would you recommend it?”
- “What did you like or dislike?”
- “Should I mark this as watched/read/finished/played?”
- “Do you want me to remind you when the next season/book/game/DLC comes out?”

This data could enable future recall, reminders, and recommendations:

- “Suggest a movie to watch tonight.”
- “Find something like Palm Springs.”
- “What shows did I start but not finish?”
- “What movies did I rate highly?”
- “What games have I played that are like this?”
- “Are any shows I watch getting new seasons soon?”

## Specialized Media Views

Cider likely needs specialized views or tabs for media and interest libraries rather than treating all media as generic bookmarks.

Potential media surfaces:

- Movies
- TV Shows
- Books
- Games
- Watchlist / backlog
- Currently watching / reading / playing
- Completed / watched / read / played
- Ratings and reactions
- Upcoming seasons, releases, sequels, DLC, or adaptations
- Recommendations based on saved/rated items

These views should make Cider feel like a personal media memory system: part library, part tracker, part taste profile, part recommendation engine.

## First Media Library Pilot

Before Cider has a full backend/frontend media tab, the best first step is to seed a small structured Markdown-based media library that Hermes can maintain and Cider can later turn into real models/views.

Recommended starting point:

- create a simple `Media Library` note/doc as the source of truth
- start with shows, movies, and games the user already likes
- capture status, rating, tags, why the user likes it, and follow-up needs
- prefer user-provided titles and links over automatic guessing
- optionally import/summarize Trakt watchlist/history later if the user authorizes it
- use the growing Markdown list to discover the fields Cider needs before building the UI

Useful initial fields:

- title
- type: TV show / movie / game / book
- status: interested / watching / watched / playing / finished / dropped
- progress: season/episode, book progress, game progress if relevant
- rating or vibe
- tags/genres
- why the user likes it
- similar-to references
- follow-up: new season, sequel, DLC, release date, remind later
- source link: Trakt, IMDb, Steam, YouTube trailer, article, etc.

This lets the assistant begin acting as a memory companion immediately while keeping the implementation lightweight and local-first.

## Personalized Recommendations

Cider should eventually recommend things based on the user's saved and rated libraries.

Recommendation inputs could include:

- saved bookmarks
- watched/read/played status
- ratings
- tags/genres
- notes/reactions
- repeated interests
- current context/time
- existing watchlists or reading lists

Recommendation outputs should be explainable:

- why it is suggested
- what saved items it relates to
- what uncertainty exists
- whether it is based on user taste vs general popularity

## RSS / News / Interest Briefing

Cider could eventually support a personalized RSS/news briefing based on what the user saves and cares about.

Example:

If the user saves many Codex, ChatGPT, Claude Code, Hermes, AI-agent, or local-first app bookmarks, Cider could infer that this is an active interest area and offer a daily/weekly digest.

The assistant could say:

> “You’ve saved a lot of Codex/ChatGPT/agent workflow links lately. Want me to include AI coding-agent news in your daily briefing?”

Potential sources:

- RSS feeds
- blogs
- GitHub releases
- product changelogs
- arXiv/papers
- saved creator accounts
- manually subscribed topics

The briefing should be user-controlled and transparent:

- show why a topic is included
- allow muting topics
- allow adding/removing sources
- avoid overwhelming the user
- distinguish saved personal knowledge from external news

## Agent as Life Wiki Interface

The assistant should be able to answer questions from Cider as a personal life wiki:

- “What did I save about Codex?”
- “What restaurants did I want to try?”
- “What movies did I save?”
- “What events do I have coming up?”
- “What todos are stale?”
- “What was that app idea we talked about?”
- “Who was that person/contact?”

The assistant should cite or reference Cider items where possible so recall remains grounded in the vault, not hallucinated memory.

## Product Principle

Cider should make the assistant better, and the assistant should make Cider better.

Every real use should feed one of:

- better routing rules
- better metadata
- better recall
- better Dashboard modules
- better briefing logic
- better CLI/app affordances
- better personal libraries
- better product direction

This is how Cider becomes the user's dream knowledge app rather than just another bookmark manager or notes app.
