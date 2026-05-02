# Cider Site Product Hub Direction

**Created:** 2026-04-29

## Purpose

`cider.so` should become the public product hub for the Cider ecosystem, not only a landing page for the macOS app and not a direct jump into a bare web-app login screen.

The goal is for visitors to move between the macOS app, Web App, and future iOS app like they are moving between product tabs in one cohesive Cider experience.

## Product Direction

The main site should keep the cinematic Cider identity: dark native-Mac atmosphere, amber ember/ribbon visuals, compact top rail, tilted status badges, and product-window previews.

The top navigation should eventually behave like a product switcher:

```text
cider.so        -> Cider product hub / macOS-first story
cider.so/web    -> Web App story, testing status, login/signup entry
cider.so/ios    -> iOS App story, status, TestFlight/App Store entry
app.cider.so    -> signed-in web application
```

The important feeling: clicking **Web App** should not feel like being sent to a separate random SaaS login page. It should feel like switching to the Web App tab of the same Cider product.

## Recommended Flow

### Current Stable Structure

Keep these separate for now:

```text
cider.so / www.cider.so -> marketing/product site
app.cider.so            -> actual authenticated web app
```

This keeps deployments and authentication clean while avoiding the domain confusion that happened when the marketing site and web app shared one Vercel project.

### Near-Term Web App Flow

The **Web App Testing** link on `cider.so` should eventually point to:

```text
https://cider.so/web
```

That page should:

- Reuse the same top rail as the current Cider site.
- Mark **Web App** as the active product tab.
- Keep the amber **Testing** badge.
- Explain that Cider Web is live but still in testing.
- Show Web App-specific product visuals or screenshots.
- Provide clear actions:
  - **Open Web App** -> `https://app.cider.so/home`
  - **Sign in** -> `https://app.cider.so/login`
  - **Create account** -> `https://app.cider.so/signup`

If the user is unauthenticated, `app.cider.so/home` can still redirect to login, but the login page should visually match the Cider site.

### Near-Term Auth Pages

The web app auth pages should be redesigned to feel like part of the Cider site:

- Same Cider mark and warm top rail.
- Same dark/ember background language.
- Same active **Web App Testing** state.
- Login/signup form presented like a Cider app window, not a generic SaaS card.
- Copy should reinforce context: "Cider Web is in testing. Sign in to continue to your vault."

This preserves clean app-domain authentication while making the handoff feel intentional.

## Future iOS Flow

When the iOS app is ready to show publicly, add:

```text
https://cider.so/ios
```

The iOS page should follow the same pattern as `/web`:

- Same top rail and product-tab structure.
- **iOS App** active state.
- Status badge such as **Soon**, **TestFlight**, or **Beta**.
- iOS-specific story, screenshots, and install path.

## Later Same-Domain Option

If seamlessness becomes more important than deployment separation, consider consolidating the marketing site and web app into one app/project so signed-in web routes can live under:

```text
cider.so/app
cider.so/login
cider.so/signup
```

This would create the most seamless domain experience, but it is a larger architecture change. It requires careful routing, auth, deployment, and ownership decisions. It should not be the immediate fix.

## What Not To Do

- Do not send the top nav directly from `cider.so` to a plain, generic login page.
- Do not put the marketing site and web app back into one ambiguous Vercel project without a clear routing/deployment plan.
- Do not make a login modal on `cider.so` as the first solution. Cross-domain auth and session handling would add complexity before the product structure is settled.
- Do not make `/web` a generic feature section. It should feel like a full product tab.

## Implementation Order

1. Keep `cider.so` as the public Cider site and `app.cider.so` as the authenticated web app.
2. Redesign `app.cider.so/login` and `/signup` so the auth experience visually matches `cider.so`.
3. Add `cider.so/web` as a Web App product page.
4. Change the main top rail **Web App Testing** link to `https://cider.so/web`.
5. Add `cider.so/ios` when there is enough iOS material to show.
6. Revisit same-domain app routing only after the product tabs are working and the web app direction is stable.
