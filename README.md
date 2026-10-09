<div align="center">

<img src="docs/icon.png" width="128" alt="Claudify icon">

# Claudify

**Your Claude usage limits, always one glance away in the macOS menu bar.**

[![macOS](https://img.shields.io/badge/macOS-26.5%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-D97757.svg)](LICENSE)

</div>

---

Claudify is a small, native menu bar app that shows the same numbers as the `/usage` command in [Claude Code](https://docs.claude.com/en/docs/claude-code/overview): how much of your **5-hour session** and **7-day weekly** limits you've used, and when they reset. You don't need to open a terminal or a browser to check.

## ✨ Features

- **Live percentage in the menu bar**: your current session usage sits next to the Claudify gauge icon.
- **Session and weekly limits**: progress bars for the 5-hour and 7-day windows, colored green, orange, or red as you get closer to the limit.
- **Reset countdowns**: shows when each window resets (`2h 14m`, `3d 6h`, …) and updates every second.
- **Plan badge**: shows which Claude plan you're on (Pro, Max 5x, Max 20x, Team, …).
- **Claude Code version**: shows the version of Claude Code installed on your Mac.
- **Zero setup**: reuses the login you already have in Claude Code. There's no API key to paste.
- **Lightweight**: pure SwiftUI with no dependencies and no Dock icon. It refreshes once a minute.

## 📦 Requirements

- macOS 26.5 or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code/setup), logged in with a Claude subscription (Pro, Max, Team, or Enterprise)
- Xcode 26 or later (to build from source)

## 🚀 Getting started

```bash
git clone https://github.com/st3k0/Claudify.git
cd Claudify
open Claudify.xcodeproj
```

Choose your own signing team under **Signing & Capabilities**, then press **⌘R**. Claudify appears in the menu bar.

> [!TIP]
> To have Claudify start automatically, add it under **System Settings → General → Login Items**.

The first time Claudify runs, macOS asks whether it can read the `Claude Code-credentials` item from your Keychain. Choose **Always Allow** so you aren't asked again.

## 🔍 How it works

1. **Credentials:** Claudify reads the OAuth token Claude Code saves in your login Keychain (`Claude Code-credentials`). If that's missing, it falls back to `~/.claude/.credentials.json`.
2. **Usage:** It calls Anthropic's OAuth usage endpoint, which is the same source `/usage` uses, to get usage for the 5-hour and 7-day windows.
3. **Token refresh:** When the access token is about to expire, Claudify refreshes it and saves the new token back to the same place, so Claude Code keeps working.
4. **Plan and version:** The plan comes from your saved credentials. The Claude Code version comes from the installed `claude` binary; Claudify never launches it.

### Privacy

Claudify talks **only** to `api.anthropic.com`. It has no analytics, no telemetry, and no third-party servers. Your token stays on your Mac.

## 🗂 Project structure

| File | Purpose |
| --- | --- |
| `Claudify/ClaudifyApp.swift` | App entry point and the `MenuBarExtra` label |
| `Claudify/ContentView.swift` | The popover UI: header, usage rows, footer |
| `Claudify/UsageMonitor.swift` | Credential loading, token refresh, usage API, plan and version detection |

## 🛠 Troubleshooting

| Message | Fix |
| --- | --- |
| *Log in with Claude Code first.* | Run `claude` in a terminal and complete `/login`. |
| *Session expired — run Claude Code to re-auth.* | Open Claude Code once so it can sign in again, then click **Refresh**. |
| *Anthropic API returned an error.* | Usually temporary. Wait a minute or click **Refresh**. |

## 🤝 Contributing

Issues and pull requests are welcome! For larger changes, please open an issue first so we can agree on the approach.

1. Fork the repo and create a branch: `git checkout -b feature/my-idea`
2. Commit your changes
3. Open a pull request

## ⚠️ Disclaimer

Claudify is an independent, community project. It is **not affiliated with, endorsed by, or sponsored by Anthropic**. "Claude" is a trademark of Anthropic, PBC. The Claudify icon is an original design (source: [`docs/icon.svg`](docs/icon.svg), regenerate with [`docs/generate_icon.py`](docs/generate_icon.py)). The usage endpoint Claudify uses is undocumented and could change at any time.

## 📄 License

Released under the [MIT License](LICENSE).
