# Usage AI

An iOS Home Screen **widget** that shows a ring of your connected AI services'
usage — how much of each cap you have left, across **both** the short (5-hour)
and **weekly** windows these plans now enforce, plus when each resets. The
layout mirrors the iOS *Batteries* widget (and the Codex usage widget): a
horizontal row of rings, each with the provider's glyph, a fill showing the
most-depleted window remaining, and a caption listing every tier
("5h 99% · Wk 100%").

Supported providers: **OpenAI**, **Anthropic**, **Google** — connect any subset.

## The honest state of "usage left"

Modern subscription plans enforce **multiple caps at once** — a rolling 5-hour
limit *and* a weekly limit (this is what the Codex/Claude apps show). Those
numbers come from the same **authenticated endpoints the first-party CLIs use**,
reached by signing in with OAuth. There is no separately-documented public API
for them, so this app is honest about what each path can deliver:

| Provider  | Sign-in | What the ring shows | Reliability |
|-----------|---------|---------------------|-------------|
| **Anthropic** | OAuth (Claude login, **the working path**) | 5-hour + weekly session windows, read from the API response's rate-limit headers | Real, but the "unified" headers are undocumented — parsed best-effort |
| **OpenAI** | OAuth ("Sign in with ChatGPT", client ID **you supply**) *or* API key | Plan 5h/weekly via Codex's usage endpoint *(endpoint left as a TODO)*; API key shows the rate-limit window | Key path works today; OAuth plan-usage needs the private endpoint wired in |
| **Google** | OAuth (client ID **you supply**) *or* API key | Connection status only — Google exposes no subscription usage window | Works; no usage numbers to show |

Ring semantics match a battery: the arc is the **remaining** fraction of the
**most-depleted** window, turning **orange** under 25% and **red** under 10%.

> **Caveats you should know.** The OAuth flows use the providers' **first-party**
> clients (Claude / ChatGPT), and the usage surfaces are undocumented. This is a
> Terms-of-Service gray area and can change without notice. Anthropic's flow is
> pre-filled with the public Claude client ID; OpenAI and Google need a client ID
> you provide in `Shared/OAuth/OAuthConfig.swift`.

## How auth works

- **PKCE OAuth 2.0** (`Shared/OAuth/`): `PKCE.swift` generates the challenge,
  `OAuthConfig.swift` holds per-provider endpoints/clients, `OAuthClient.swift`
  exchanges and refreshes tokens (no UI — the widget refreshes headlessly too),
  and `WebAuthenticator.swift` (app only) drives `ASWebAuthenticationSession`.
- **Two callback shapes:** Google/OpenAI use a custom-scheme redirect the app
  intercepts; Anthropic's first-party client can't be redirected to us, so it
  uses a **copy-the-code** flow (authorize in the browser, paste the code back).
- **Storage:** tokens and keys are stored as a `Credential` (`Shared/
  Credential.swift`) in the shared keychain; `CredentialManager` transparently
  refreshes an expiring access token before each use.

## Project layout

```
UsageAI.xcodeproj          # Two targets: the app and the widget extension
├─ UsageAI/                # App target (SwiftUI)
│  ├─ UsageAIApp.swift
│  ├─ ContentView.swift        # Dashboard: rings + per-service rows
│  ├─ ConnectProviderView.swift# OAuth sign-in and/or API-key entry
│  └─ WebAuthenticator.swift   # ASWebAuthenticationSession (scheme + manual)
├─ UsageAIWidget/          # WidgetKit extension (small + medium)
│  └─ UsageAIWidget.swift      # Widget, TimelineProvider, ring layouts
└─ Shared/                 # Compiled into BOTH targets
   ├─ Provider.swift            # ProviderID: names, colors, glyphs, auth
   ├─ UsageSnapshot.swift       # UsageWindow (5h/weekly/rate) + snapshot model
   ├─ UsageProviders.swift      # OpenAI / Anthropic / Google clients
   ├─ UsageRefresher.swift      # Concurrent refresh + persist
   ├─ Credential.swift          # apiKey|oauth credential + keychain + refresh
   ├─ OAuth/                    # PKCE, token, config, token client
   ├─ RingView.swift            # One ring (remaining-based)
   └─ UsageRingsView.swift      # The row of rings (the circled layout)
```

## Getting started

1. Open `UsageAI.xcodeproj` in **Xcode 15+**. Set your **Team** on both targets
   (App Groups capability with `group.fyi.jono.UsageAI` is already declared).
2. Run on a device/simulator (iOS 17+).
3. Connect a service:
   - **Anthropic:** tap *Open sign-in*, authorize with your Claude account, copy
     the code shown, paste it back, *Connect*. Works out of the box.
   - **OpenAI:** paste an API key to get the rate-limit ring today; to get 5h/
     weekly, add a "Sign in with ChatGPT" client ID in `OAuthConfig.swift` and
     wire the usage endpoint in `OpenAIUsageProvider`.
   - **Google:** add an iOS OAuth client ID in `OAuthConfig.swift`, or paste an
     API key. (Ring shows connection status only.)
4. Long-press the Home Screen → add the **AI Usage** widget (small or medium).

Get API keys: [OpenAI](https://platform.openai.com/api-keys) ·
[Anthropic](https://console.anthropic.com/settings/keys) ·
[Google](https://aistudio.google.com/app/apikey).

### Regenerating the project (optional)

The committed `.xcodeproj` works as-is. A [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec (`project.yml`) is included if you'd rather regenerate it:
`brew install xcodegen && xcodegen generate`.

## Privacy

Tokens and keys never leave the device except in requests to the provider they
belong to. Usage snapshots live only in the app's App Group container. No
analytics, no third-party networking.
