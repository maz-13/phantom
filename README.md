<h1 align="center">
  <br>
  👻 Phantom
  <br>
</h1>

<p align="center">
  A macOS terminal for AI agents, built on <a href="https://github.com/ghostty-org/ghostty">Ghostty</a>.
</p>

<p align="center">
  <a href="#about">About</a> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#building">Building</a>
</p>

---

## About

Phantom is a fork of Ghostty for macOS, built around the idea that modern terminal workflows — especially with AI coding agents — involve juggling many sessions at once. You need to run agents, watch servers, tail logs, and still get work done in the same window.

Phantom adds a **surface shelf**: a sidebar that lets you park terminal sessions, switch between them like browser tabs, and bring them all back at once. Everything else is stock Ghostty — GPU-accelerated, native macOS, fully compatible with your existing config.

## Features

**Surface Shelf**
A sidebar that holds all your terminal sessions — active splits and shelved ones — in one place.

| Shortcut | Action |
|---|---|
| `Cmd+S` | Toggle sidebar |
| `Cmd+Shift+H` | Shelve current pane |
| `Cmd+Shift+S` | Shelve everything except focused pane |
| `Cmd+Shift+A` | Bring all shelved panes back |

- Click a shelved session to swap it in (browser-tab behavior)
- Drag a shelved session onto any pane to split left/right/top/bottom
- Activity indicators show which sessions are still running

## Install

Download the latest release, unzip, and run:

```bash
xattr -cr Phantom.app
```

Then double-click to open. The `xattr` command is required because Phantom isn't notarized yet — it clears the macOS quarantine flag.

## Building

Requires Xcode and [Nushell](https://www.nushell.sh).

```bash
git clone https://github.com/maz-13/phantom
cd phantom/macos
nu build.nu --configuration Release --action build
sh open.sh
```

## Credits

Phantom is built on top of [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto. All terminal rendering, configuration, and core functionality comes from Ghostty. Phantom adds the surface shelf on top.

Built by [Maz](https://github.com/maz-13).
