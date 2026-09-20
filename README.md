# smenu

A small macOS menu bar utility covering the parts of Bartender I actually use.
Requires macOS 26+ (built and tested on macOS 27).

## Features

- **Capsule menu bar** – draws a Liquid Glass (or frosted) capsule beneath the transparent menu bar,
  either as one full-width bar or as split pills around the app menus and the status items.
- **Smaller menu bar** – sets `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` (Default / Compact 6 / Tight 3).
  Apps pick the new spacing up when they relaunch; log out to apply it everywhere.
- **Hide section** – click the chevron to collapse everything left of the `│` divider.
  ⌘-drag items across the divider to choose what hides.

Right-click (or ⌥-click) the chevron for settings, launch at login, and quit.

## Build

```
make run       # build, bundle, ad-hoc sign, launch build/smenu.app
make install   # copy to /Applications
```

## Permissions

Split Pills needs Accessibility access: macOS 27 renders all status items inside a single
`MenuBarAgent` window, so item positions are only available through the Accessibility API.
The app is ad-hoc signed, so the grant must be re-approved after each rebuild.

The capsule sits one window level below the menu bar, so it relies on the default transparent
menu bar (System Settings → Menu Bar → "Show menu bar background" off).
