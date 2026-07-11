# Usage AI

An iOS Home Screen **widget** that shows a ring of your connected AI services'
session token usage — and when each usage window resets. The layout mirrors the
iOS *Batteries* widget: a horizontal row of rings, each with the provider's
glyph in the center, a fill showing how much of the current window you've used,
and a caption with the percentage and reset time.

Supported providers: **OpenAI**, **Anthropic**, and **Google** (connect one, two,
or all three).

<p align="center"><em>App target + WidgetKit extension, SwiftUI, iOS 17+.</em></p>

## What the rings mean

Each provider is authenticated with an **API key** you paste into the app. On
every refresh the app makes one tiny request and reads the provider's
**rate-limit response headers**, which describe the token budget for the current
rolling window and when it resets — the closest public analogue to a "session":

| Provider  | How usage is read | Reset time |
|-----------|-------------------|------------|
| OpenAI    | `x-ratelimit-limit-tokens` / `x-ratelimit-remaining-tokens` headers | `x-ratelimit-reset-tokens` (e.g. `2m59s`) |
| Anthropic | `anthropic-ratelimit-tokens-limit` / `-remaining` headers | `anthropic-ratelimit-tokens-reset` (RFC3339) |
| Google    | Key is validated; **no usage window is exposed** by the API | — (ring is drawn indeterminate) |

The ring turns **orange** past 75% and **red** past 90% of the window.

> **Note on subscription/session limits:** consumer subscription plans (ChatGPT
> Plus, Claude Pro/Max, Gemini Advanced) do **not** expose a public "remaining
> session usage" API. This app therefore reads the **API** rate-limit window for
> the key you provide. If those providers publish a session-usage endpoint in the
> future, add it in `Shared/UsageProviders.swift` — the rest of the app is
> already wired for it.

## Project layout

```
UsageAI.xcodeproj          # Two targets: the app and the widget extension
├─ UsageAI/                # App target (SwiftUI)
│  ├─ UsageAIApp.swift
│  ├─ ContentView.swift        # Dashboard: rings + per-service rows
│  ├─ ConnectProviderView.swift# Paste + validate an API key
│  └─ UsageAI.entitlements     # App Group
├─ UsageAIWidget/          # WidgetKit extension
│  ├─ UsageAIWidgetBundle.swift
│  ├─ UsageAIWidget.swift      # Widget, TimelineProvider, small/medium views
│  ├─ Info.plist               # NSExtension → widgetkit-extension
│  └─ UsageAIWidget.entitlements
└─ Shared/                 # Compiled into BOTH targets
   ├─ AppGroup.swift            # Shared identifiers
   ├─ Provider.swift            # ProviderID: names, colors, glyphs, key URLs
   ├─ UsageSnapshot.swift       # The data model persisted + rendered
   ├─ KeychainStore.swift       # API keys in the shared keychain
   ├─ UsageStore.swift          # Snapshots + connected list in shared defaults
   ├─ RateLimitParsing.swift    # Header → Int / Date / duration helpers
   ├─ UsageProviders.swift      # OpenAI / Anthropic / Google clients
   ├─ UsageRefresher.swift      # Concurrent refresh + persist
   ├─ Formatting.swift          # "resets in 2h 14m" strings
   ├─ RingView.swift            # One ring
   └─ UsageRingsView.swift      # The row of rings (the circled layout)
```

The app and widget share data through an **App Group**
(`group.fyi.jono.UsageAI`): connected-provider list and snapshots live in the
group's `UserDefaults`, and API keys live in the keychain (the App Group id
doubles as the keychain access group, so no Team ID is hardcoded). The app calls
`WidgetCenter.reloadAllTimelines()` whenever data changes; the widget also
refreshes itself on its timeline and schedules the next reload just before the
soonest window resets.

## Getting started

1. Open `UsageAI.xcodeproj` in **Xcode 15 or newer**.
2. Select the **UsageAI** target → *Signing & Capabilities* and set your
   **Team**. Do the same for the **UsageAIWidgetExtension** target.
3. Both targets already declare the **App Groups** capability with
   `group.fyi.jono.UsageAI`. If you change the bundle identifiers, update the
   group id in the entitlements files and in `Shared/AppGroup.swift` to match.
4. Build & run on a device or simulator (iOS 17+).
5. In the app, tap a service, paste an API key, and *Connect*. Then long-press
   your Home Screen → add the **AI Usage** widget (small or medium).

Get API keys here: [OpenAI](https://platform.openai.com/api-keys) ·
[Anthropic](https://console.anthropic.com/settings/keys) ·
[Google](https://aistudio.google.com/app/apikey).

### Regenerating the project (optional)

The committed `.xcodeproj` works as-is. If you prefer a declarative source of
truth, a [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec is included:

```sh
brew install xcodegen
xcodegen generate
```

## Privacy

API keys never leave the device except in requests to the provider you entered
them for. Usage snapshots are stored only in the app's App Group container. There
is no analytics or third-party networking.
