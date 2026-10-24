<p align="center"><img src="docs/header.png" alt="Pointsman — Every link goes to the browser it belongs in." width="100%"></p>

Pointsman is a macOS menu bar app that sits in front of your browsers. Set it as your default browser, describe once how you use each real browser, and every link you click is sent to the right one: work links to your work browser, personal links to your personal one.

A pointsman is the railway worker who throws the switch that sends a train onto the right track. Pointsman does that for links.

## How it works

When you click a link, macOS hands it to Pointsman along with the app it came from (Slack, Mail, Terminal, …). Pointsman asks [Jev](https://openrouter.ai/typesafe/jev-1.13), a small model that picks between options instead of writing text, which of your enabled browsers fits best. It sends Jev:

- your context, one or two sentences about how you work;
- the description you wrote for each enabled browser;
- the app the link came from;
- the URL, **without** its query string, fragment or credentials.

Jev returns a probability for each browser, plus a `none` option. Then:

```
Pointsman paused?                    → fallback browser
localhost / 127.0.0.1 / ::1?         → fallback browser (OAuth callbacks, dev servers)
no browser enabled, or no API key?   → fallback browser
Jev's top answer ≥ threshold (60%)   → that browser
"none", below threshold, error, or no answer within 1.5 s → fallback browser
```

A wrong guess costs you one link in the wrong browser; it never blocks a link. In our tests a decision takes 200–400 ms and costs about $0.00002.

## Features

- **Knows where the link came from.** Uses the sender of the macOS `GetURL` Apple Event, resolved to the enclosing app for helper processes (Electron, XPC). Command-line tools keep their binary name, so "opened from `gh`" is a signal too.
- **Plain-language rules.** No regex or domain lists: you describe each browser in a sentence.
- **Safe by default.** Uncertain decisions go to the fallback browser you choose.
- **Test bench.** Paste a URL and the app it was clicked from in Settings → Decision to see Jev's probabilities and where the threshold falls.
- **Decision log.** Every routed link is logged as one JSON line (redacted URL, source app, target, reason, latency).
- **Menu bar status.** The icon shows a badge when something is missing (not the default browser, no API key, no browser enabled).

## Requirements

- macOS 15 (Sequoia) or later on Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`), for `swiftc`
- An [OpenRouter](https://openrouter.ai) API key

## Install

There is no signed release yet; build from source:

```bash
git clone https://github.com/romainjeff/pointsman.git
cd pointsman
./build.sh --install
```

`build.sh` runs the self-test, compiles the app with `swiftc` (no Xcode project, no SwiftPM), signs it ad hoc and copies it to `~/Applications/Pointsman.app`, then launches it. Without `--install` it only builds `build/Pointsman.app`.

## Setup

1. Click the Pointsman icon in the menu bar, then **Settings…** (⌘,).
2. **General**: paste your OpenRouter key (stored in the macOS Keychain) and click **Make default**. macOS asks you to confirm.
3. **Browsers**: write your context, switch on the browsers you want Pointsman to use, and describe what each one is for. For example:
   - *Context*: "I'm a developer. Work links go in Chrome, personal browsing in Safari."
   - *Google Chrome*: "Work: GitHub, Linear, Notion, Google Docs, anything signed in with my work account."
   - *Safari*: "Personal: news, shopping, YouTube, banking."
4. **Decision**: pick the fallback browser and the confidence threshold, and try a few links on the test bench.

Write descriptions in English; Jev works best in it.

## Configuration

| What | Where |
|---|---|
| Settings (context, browsers, fallback, threshold, model) | `~/.config/link-router/config.json` |
| OpenRouter key | Keychain, service `link-router`. `OPENROUTER_API_KEY` overrides it when set. |
| Decision log | `~/Library/Logs/LinkRouter/decisions.jsonl` (menu → **Open log**) |

The config is plain JSON and can be edited by hand while the app is closed.

## Privacy

- Each link you click is sent to OpenRouter with your context and browser descriptions. Requests ask providers not to retain data (`data_collection: deny`).
- Query strings and fragments are never sent: they often hold tokens (magic links, OAuth codes). Only scheme, host and path leave your Mac.
- Local URLs (`localhost`, `127.0.0.1`, `::1`) never leave your Mac.
- Switch off **Active** at the top of Settings to send every link to the fallback browser without any network call.
- The decision log stays on your Mac.

## Uninstall

1. Pick another default browser in System Settings → Desktop & Dock → Default web browser.
2. Quit Pointsman from the menu bar, then delete `~/Applications/Pointsman.app`.
3. Optionally remove `~/.config/link-router/`, `~/Library/Logs/LinkRouter/` and the `link-router` Keychain item.

## Troubleshooting

- **Every link goes to the fallback.** Check the menu bar icon for a badge, then the `reason` field in the decision log (`no key`, `no candidate`, `unsure 45%`, `error: …`).
- **Keychain prompt after rebuilding.** Each build gets a new ad hoc signature, so macOS asks again for access to the key. Click *Always Allow*.
- **The source app shows as `osascript` or a binary name.** Links opened with `open` or from scripts have no app bundle. Clicks from real apps resolve correctly.

## Project layout

```
Sources/App.swift        Menu bar, Settings window (SwiftUI), Apple Event handler
Sources/Router.swift     Config, Keychain, Jev client, decision flow, log
Sources/Decision.swift   Pure helpers (URL redaction, pick by threshold)
Tests/SelfTest.swift     Self-test run by build.sh
Resources/               App icon and menu bar icons (SVG)
docs/                    README header (HTML source and PNG), intro video
```

## Roadmap

- Chrome and Arc profiles as separate destinations
- A quick picker when Jev hesitates, instead of a silent fallback
- Measure accuracy on real links before trusting the threshold
- Signed and notarized releases

## Contributing

Issues and pull requests are welcome. Keep changes small; the app is intentionally a few hundred lines of Swift with no dependencies. Run `./build.sh` before opening a PR: it fails if the self-test fails.

## License

[MIT](LICENSE)
