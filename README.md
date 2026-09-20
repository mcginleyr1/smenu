# smenu

A small macOS menu bar utility covering the parts of Bartender I actually use.
Requires macOS 26+ (built and tested on macOS 27).

## Features

- **Capsule menu bar** – draws a translucent light or dark capsule over the menu bar,
  either as one full-width bar or as split pills around the app menus and the status items.
- **Smaller menu bar** – sets `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` (Default / Compact 6 / Tight 3).
  Apps pick the new spacing up when they relaunch; log out to apply it everywhere.
  Apple's own items (battery, Wi-Fi, Control Center, clock) ignore these keys on macOS 27.

- **Hide section** – "Hide Icons Left of │" tucks everything left of the `│` divider away behind
  macOS's own `«` overflow marker. Untick it to ⌘-drag items across the divider and choose what hides.

Click the `│` (or, while hiding, the empty bar space left of `«`) for the menu: hiding, capsule,
spacing, launch at login, and quit.

macOS 27 evicts over-wide status items, so the usual "stretch the divider to 10000pt" trick does not
work. The divider instead fills the room up to the notch; macOS then moves the items that no longer
fit to the left of the notch and shows its own `»` overflow marker, which smenu cannot remove.

## Build

```
make run       # build, bundle, ad-hoc sign, launch build/smenu.app
make install   # copy to /Applications
make icon      # regenerate AppIcon.icns from scripts/make-icon.swift
```

## Permissions

Split Pills needs Accessibility access: macOS 27 renders all status items inside a single
`MenuBarAgent` window, so item positions are only available through the Accessibility API.
The Makefile signs with the `Apple Development` identity so the grant survives rebuilds;
`make SIGN=- app` signs ad-hoc instead, which resets the grant on every build.
