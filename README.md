# Desktop Icons

A tiny macOS menu bar app that shows or hides all your desktop icons with one click or a global keyboard shortcut.

The app lives only in the menu bar (no Dock icon). Its icon is an eye over a file; the eye is slashed while the icons are hidden.

## Features

- Menu bar only: no Dock icon, no windows unless you open the shortcut settings
- Menu with:
  - **Hide / Show All Desktop Icons**
  - **Set Shortcut…**
  - **Quit App**
- Global keyboard shortcut (default: `⌃⌥⌘H`), fully customizable
- No special permissions required (no Accessibility, no Automation)
- Localized automatically: English (default), Italian, Spanish, French, German
- Single Swift file, no external dependencies

## Requirements

- macOS 11 (Big Sur) or later
- Xcode Command Line Tools to build: `xcode-select --install`

## Build

```bash
git clone <your-repo-url>
cd DesktopIcons
chmod +x build.sh
./build.sh
open "Desktop Icons.app"
```

The script compiles `main.swift` for your Mac's architecture, creates the `.app` bundle, copies the localization files, and signs the app ad-hoc.

To keep it, drag `Desktop Icons.app` to `/Applications`. To launch it at login, add it under **System Settings → General → Login Items**.

> Because the app is signed ad-hoc, macOS may block the first launch if you downloaded a prebuilt copy. Open it from **System Settings → Privacy & Security**, or right-click the app and choose **Open**.

## Usage

- Click the menu bar icon and choose **Hide All Desktop Icons** or **Show All Desktop Icons**.
- Or press the global shortcut (default `⌃⌥⌘H`).
- To change the shortcut, choose **Set Shortcut…**, click the button, and press the new combination. At least one modifier (`⌘ ⌥ ⌃ ⇧`) is required. Press `Esc` to cancel. You can also restore the default or remove the shortcut. The choice is saved between launches.

## How it works

Hiding and showing is done by toggling the Finder's `CreateDesktop` preference and relaunching the Finder:

```bash
defaults write com.apple.finder CreateDesktop -bool false   # hide
defaults write com.apple.finder CreateDesktop -bool true    # show
killall Finder
```

This is the standard approach, as macOS has no public API for it. Relaunching the Finder briefly closes and reopens Finder windows.

The global shortcut uses Carbon's `RegisterEventHotKey`, which works without Accessibility permission.

### Behavior on quit

By default, if the icons are hidden when you quit the app, they are shown again so they don't stay hidden without the app to bring them back. To disable this, set `restoreIconsOnQuit = false` at the top of `main.swift`.

## Troubleshooting

- **Icons are still hidden after the app crashed or was force-quit:** run `defaults write com.apple.finder CreateDesktop -bool true && killall Finder`.
- **The shortcut doesn't work:** another app may already use that combination. Pick a different one in **Set Shortcut…**.
- **Menu bar icon not visible:** the menu bar may be full; try quitting other menu bar apps or use a menu bar manager.

## License

Desktop Icons is free software, released under the GNU General Public License v3.0 (or, at your option, any later version).le.
