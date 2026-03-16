# Bookmark Enrichment Strategy

## Current Desktop Pipeline

The macOS app has a three-tier enrichment system in `BookmarksStorage.fetchEnrichmentPayload()`:

```
Tier 1: HTTP fetch + BookmarkMetadataParser (static HTML parsing)
  - og:image, og:title, twitter:image, JSON-LD, favicon
  - Site-specific regex for Reddit (i.redd.it) and X (pbs.twimg.com)
  ↓ if no real thumbnail found...

Tier 2: oEmbed fallback (TikTok, Instagram, Spotify)
  ↓ if still missing title/thumbnail...

Tier 3: WebViewMetadataExtractor (headless WKWebView)
  - Renders full page with JavaScript
  - Handles WAF challenges (retries up to 3x)
  - Takes screenshot as last-resort thumbnail
```

### What's Already Working Well
- General HTML meta tag parsing (og:image, twitter:image, etc.)
- JSON-LD extraction
- Favicon fallback with priority (apple-touch-icon > shortcut icon > icon)
- Reddit placeholder image filtering
- X/Twitter media URL regex extraction
- oEmbed for TikTok, Instagram, Spotify
- WebView fallback with screenshot capture

### What's Missing / Gaps
- Reddit HTML parsing is unreliable (meta tags often point to placeholders)
- X/Twitter requires JS rendering for most content
- No oEmbed for YouTube, Medium, Substack, LinkedIn, Vimeo
- No Reddit `.json` API usage
- No server-side enrichment (iOS/web bookmarks wait for desktop)

---

## Free Alternatives (No Cloudflare Needed)

Before reaching for Cloudflare, there are platform-specific APIs that are free, auth-free, and more reliable than HTML scraping.

### Reddit `.json` Endpoint

Append `.json` to any Reddit URL for structured data. No auth required.

```
GET https://www.reddit.com/r/programming/comments/abc123/title/.json
```

Returns:
```json
{
  "data": {
    "title": "Post title",
    "selftext": "Post body...",
    "thumbnail": "https://...",
    "preview": {
      "images": [{ "source": { "url": "https://i.redd.it/..." } }]
    },
    "url": "https://linked-content.com"
  }
}
```

- `preview.images[0].source.url` gives the highest quality thumbnail
- Rate limit: ~60 req/min (needs proper User-Agent)
- Much more reliable than parsing Reddit's HTML

Reddit also supports oEmbed: `https://www.reddit.com/oembed?url=...&format=json`

### X/Twitter oEmbed

```
GET https://publish.twitter.com/oembed?url=https://x.com/user/status/123&format=json
```

Returns title (tweet text), author info, embed HTML — but **no thumbnail_url**. For images, the current regex approach against `pbs.twimg.com` URLs in HTML is still the best free option. The WebView fallback handles this well when static parsing fails.

### Additional oEmbed Providers to Add

These all work with no auth, return `title` + `thumbnail_url`:

| Platform | Endpoint | Reliability |
|----------|----------|------------|
| YouTube | `https://www.youtube.com/oembed?url=...&format=json` | High |
| Vimeo | `https://vimeo.com/api/oembed.json?url=...` | High |
| Medium | `https://medium.com/services/oembed?url=...&format=json` | High |
| Substack | `https://substack.com/api/v1/oembed?url=...` | High |
| LinkedIn | `https://www.linkedin.com/oembed?url=...` | Medium |
| Reddit | `https://www.reddit.com/oembed?url=...&format=json` | High |
| Flickr | `https://www.flickr.com/services/oembed/?url=...&format=json` | High |
| TikTok | `https://www.tiktok.com/oembed?url=...` | Already implemented |
| Instagram | `https://api.instagram.com/oembed?url=...` | Already implemented |
| Spotify | `https://open.spotify.com/oembed?url=...` | Already implemented |

### YouTube Thumbnail Shortcut

YouTube thumbnails are deterministic — no API call needed:
```
https://img.youtube.com/vi/{VIDEO_ID}/maxresdefault.jpg
https://img.youtube.com/vi/{VIDEO_ID}/hqdefault.jpg
```

Extract the video ID from the URL and construct the thumbnail directly.

---

## Recommended Enrichment Pipeline (Updated)

```
Tier 1: Static HTTP fetch + HTML parsing (FREE)
  - BookmarkMetadataParser (existing)
  - Works for 80-90% of sites
  ↓ if no real thumbnail...

Tier 2: Platform-specific APIs (FREE)
  - Reddit: .json endpoint (higher quality than HTML parsing)
  - YouTube: Direct thumbnail URL construction
  - oEmbed: YouTube, Vimeo, Medium, Substack, LinkedIn, Reddit, Flickr
  - oEmbed: TikTok, Instagram, Spotify (existing)
  ↓ if still missing...

Tier 3: WebView fallback (FREE, desktop only)
  - WebViewMetadataExtractor (existing)
  - Handles JS-rendered pages, WAF challenges
  - Screenshot as last-resort thumbnail
  ↓ if needed for server-side (iOS/web)...

Tier 4: Cloudflare Browser Rendering (PAID, server-side)
  - Only for server-side enrichment when no desktop client is available
  - Only for sites where Tiers 1-2 fail
  - See cost/guardrails section below
```

### Implementation Priority

1. **Add Reddit `.json` endpoint** — biggest bang for buck, Reddit is one of the hardest sites to scrape via HTML
2. **Add YouTube direct thumbnail** — no API call needed, just URL construction
3. **Expand oEmbed providers** — YouTube, Vimeo, Medium, Substack, LinkedIn, Flickr
4. **Server-side Tier 1+2 in Convex** — port static parsing + platform APIs to TypeScript for iOS/web enrichment
5. **Cloudflare Browser Rendering** — only if Tiers 1-3 still leave gaps for server-side

### Code Changes Needed (Desktop)

In `BookmarkMetadataParser.swift`:
- [ ] Add `redditJSONPayload(for:)` — fetch `.json` endpoint before regex fallback
- [ ] Add `youtubeDirectThumbnail(for:)` — construct URL from video ID
- [ ] Expand `oEmbedEndpointURL(for:)` — add YouTube, Vimeo, Medium, Substack, LinkedIn, Flickr

In `BookmarksStorage.swift` (`fetchEnrichmentPayload`):
- [ ] Call Reddit `.json` before oEmbed for reddit.com URLs
- [ ] Call YouTube thumbnail constructor for youtube.com/youtu.be URLs
- [ ] Reorder: platform-specific APIs before WebView fallback

---

## Cloudflare Browser Rendering (Tier 4)

### Overview

Cloudflare's `/crawl` endpoint renders pages server-side and returns HTML, Markdown, or JSON. Use this only for server-side enrichment (Convex actions) when the free tiers above aren't sufficient.

- **Docs:** https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/
- **Pricing:** https://developers.cloudflare.com/browser-rendering/pricing/

### Why Server-Side Enrichment Matters

Currently, enrichment only happens on the macOS desktop client:
- iOS bookmarks sit with `enrichmentStatus: "pending"` until the desktop app processes them
- Web-only users never get enrichment
- Desktop app must be running

Moving enrichment to Convex makes it client-independent.

### Pricing

| Plan | Cost | Included |
|------|------|----------|
| Workers Free | $0 | 10 min/day, 5 jobs/day, 100 pages/crawl |
| Workers Paid | $5/mo | 10 hrs/mo browser time, then $0.09/hr extra |

### Cost Estimates (Cloudflare renders only — after free tiers filter most bookmarks)

With Tiers 1-2 handling 80-90% of bookmarks, Cloudflare only processes the remainder:

| Users | Total bookmarks/day | Cloudflare renders/day | Monthly cost |
|-------|--------------------|-----------------------|-------------|
| 100 | 1,000 | ~100-200 | ~$5 (within included) |
| 1,000 | 10,000 | ~1,000-2,000 | ~$7-10 |
| 10,000 | 100,000 | ~10,000-20,000 | ~$20-40 |

### Server-Side Architecture

```
User saves bookmark (any client)
        |
        v
Convex mutation: create bookmark, enrichmentStatus: "pending"
        |
        v
Convex scheduled action: enrich bookmark
        |
        v
Step 1: fetch() + parse HTML (free)
  ↓ if insufficient...
Step 2: Platform API (Reddit .json, oEmbed, YouTube thumbnail)
  ↓ if still insufficient...
Step 3: Cloudflare /crawl with render: true ($0.09/hr)
        |
        v
Convex mutation: update bookmark with enriched data
```

### Where Cloudflare Plugs Into Desktop

In `BookmarksStorage.fetchEnrichmentPayload()`, add between oEmbed and WebView:

```swift
// After oEmbed, before WebView fallback
if shouldUseCloudflare(for: pageURL) {
    if let cfResult = await CloudflareEnrichmentService.fetch(url: pageURL) {
        return cfResult
    }
}
```

Use Cloudflare on desktop only for domains where WebView also struggles (heavily bot-protected sites). For most sites, the existing WebView fallback is fine on desktop.

---

## Guardrails to Prevent Runaway Bills

Cloudflare does NOT offer a spending cap. Protection must be built into the application.

### 1. Tiered Fetching (Most Important)

Always exhaust free tiers first. Cloudflare should only fire for ~10-20% of bookmarks at most.

### 2. Per-User Rate Limits

```
Free tier users: 20 enrichments/day
Paid tier users: 100 enrichments/day
Hard cap: 200 enrichments/day per user regardless of tier
```

Enforce in Convex before dispatching the enrichment action.

### 3. Global Budget Tracking

```
enrichmentBudget: {
  monthKey: "2026-03",
  usedSeconds: 45000,
  budgetSeconds: 360000,  // 100 hours = hard stop
  paused: false
}
```

Before each Cloudflare render, check the budget. If exceeded, leave bookmark as pending.

### 4. Queue Throttling

- Process max 10 enrichments per minute
- Increase delay during high load
- Smooths out spikes and prevents burst costs

### 5. Deduplication

- Cache enrichment results by normalized URL
- Reuse results for duplicate bookmarks across users
- Popular URLs get cached naturally

### 6. Domain Blocklist

Skip enrichment for: localhost, internal IPs, known-blocked domains, link shorteners (resolve redirect only).

### 7. Monitoring and Alerts

- Track daily enrichment counts and estimated costs
- Alert at 50%, 75%, 90% of monthly budget
- Auto-pause at budget limit
