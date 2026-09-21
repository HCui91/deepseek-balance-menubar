# DeepSeek Balance

macOS menu bar app showing your DeepSeek API credit balance.

Native Swift/AppKit. No Python, no runtime dependencies. Calls
`GET https://api.deepseek.com/user/balance` via URLSession.

## Requirements

- macOS 11+
- Swift toolchain (`xcode-select --install`)
- ImageMagick (`brew install imagemagick`) — optional, only to build an icon from your own `.ico`

## Build & run

```bash
./build_app.sh
open dist/DeepSeekBalance.app
```

The app runs as an accessory (`LSUIElement`): menu bar only, no Dock icon.
Quit via the menu bar item (⌘Q).

## API key

The key is stored in the macOS Keychain (encrypted). No config file is read or written.

Set it from the menu bar: **Set API Key…**.
First launch without a key shows `⚠ No Key`.

Lookup order:
1. `DEEPSEEK_API_KEY` environment variable (debug only)
2. macOS Keychain (`service=dev.deepseek.balance`, `account=deepseek_api_key`)

Manage from the CLI:

```bash
security find-generic-password -s dev.deepseek.balance -a deepseek_api_key
security delete-generic-password -s dev.deepseek.balance -a deepseek_api_key
```

## Menu

| Item | Action |
| --- | --- |
| Refresh Now | Refresh now (⌘R) |
| Balance Details | Per-currency total / granted / topped-up, availability, last update |
| Open DeepSeek Console | Open platform.deepseek.com/usage |
| Refresh Interval | 30 s / 1 / 5 / 15 / 30 min |
| Set API Key… | Set the key (stored in Keychain) |
| Delete Saved API Key | Remove the key from Keychain |
| Quit | Quit (⌘Q) |

The menu bar shows the balance (`¥5.96`), optionally preceded by an icon.
With multiple currency accounts, the largest balance is shown.

## Icon (optional, not included)

This repository does **not** include the DeepSeek logo: it is a trademark of
DeepSeek and is not covered by this project's license.

To show an icon in the menu bar, provide your own:

- `deepseek.ico` in the project root (converted by `build_app.sh` with ImageMagick), or
- `assets/icon.png` and `assets/icon@2x.png` (transparent PNGs, used directly)

Without an icon, the menu bar shows the balance as text only.

Tune size/gap at the top of `build_app.sh` (only affects generated icons):

```bash
ICON_HEIGHT=15   # icon height (pt)
ICON_GAP=1       # gap to the balance text (pt)
```

The icon keeps its original color. To make it adapt to light/dark menu bars,
set `icon.isTemplate = true` in `DeepSeekBalance.swift`.

## Start at login (optional)

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"'$(pwd)'/dist/DeepSeekBalance.app", hidden:false}'
```

## Dev

```bash
./build/DeepSeekBalance --check   # fetch once and print, no GUI
./build_app.sh                    # rebuild
```

## License

[MIT](LICENSE) — applies to the source code only.

The "DeepSeek" name and logo are trademarks of DeepSeek and are neither
included in nor licensed by this repository.
