# McWinBar

A Windows-style taskbar for macOS, written in Swift/AppKit. It replaces the
Dock with an always-on-top bar along the bottom of the screen: running apps
grouped per application, pinned launchers, hover thumbnails with an Aero-style
peek, a searchable Start menu, and a system tray with clock and battery.

## Features

- **Per-app window groups** in stable launch order (first launched = leftmost),
  with one underline segment per window — accent color for the frontmost
  window, muted for the rest.
- **Pinning** — right-click any running app to pin it; pinned apps stay on the
  bar as launchers when they quit.
- **Hover thumbnails** — live window snapshots on hover, plus a full-size
  Aero-style peek when you hover a thumbnail. Click a thumbnail to focus that
  exact window.
- **Start menu** — searchable list of installed apps, opened from the bar or
  with the global **Ctrl+Esc** shortcut.
- **System tray** — clock with date, battery icon with percentage, and a
  Windows-style Show Desktop button on the far right.
- **Dock replacement** — hides the macOS Dock while running and restores it on
  quit. A detached guardian process restores the Dock even if the app is
  force-killed. Notification badges are mirrored from the hidden Dock onto the
  taskbar entries, which flash on new notifications.
- **Screen-space reservation** — best-effort nudging keeps other windows from
  sitting under the bar.

## Requirements

- macOS 13 (Ventura) or later
- Swift toolchain (Xcode Command Line Tools are enough)

## Building

```sh
./build.sh
cp -R McWinBar.app /Applications/
open /Applications/McWinBar.app
```

The build script signs the bundle with a local self-signed certificate named
`Taskbar Dev Cert` when present (falling back to ad-hoc signing). Using a
stable signing identity is what lets macOS privacy permissions survive
rebuilds — create one in Keychain Access (Certificate Assistant → Create a
Certificate → Code Signing) if you plan to rebuild often.

## Permissions

On first run, grant in System Settings → Privacy & Security:

- **Accessibility** — required to list, focus, and move other apps' windows.
- **Screen Recording** — required for window thumbnails and peek previews.

## License

[CC BY-NC-ND 4.0](LICENSE) — see the LICENSE file for details.
