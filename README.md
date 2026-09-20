# smenu

A small macOS menu bar utility covering the parts of Bartender I actually use.
Requires macOS 26+ (built and tested on macOS 27).

## Features

- **Capsule menu bar** – draws a translucent light or dark capsule over the menu bar,
  either as one full-width bar or as split pills around the app menus and the status items.
- **Smaller menu bar** – sets `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` (Default / Compact 6 / Tight 3).
  Apps pick the new spacing up when they relaunch; log out to apply it everywhere.
  Apple's own items (battery, Wi-Fi, Control Center, clock) ignore these keys on macOS 27.

- **Hide section** – click the `│` divider to tuck everything left of it away; macOS shows its own `«`
  overflow marker in its place. Click the `«` to bring the items back. (smenu catches that click, so the
  system's "reveal left of the notch" never runs.) ⌘-drag items across the `│` to choose what hides.

Right-click (or ⌥-click) the `│` or the `«` for the menu: capsule, spacing, launch at login, and quit.

macOS 27 evicts over-wide status items, so the usual "stretch the divider to 10000pt" trick does not
work. The divider instead fills the room up to the notch; macOS then moves the items that no longer
fit to the left of the notch and shows its own `»` overflow marker, which smenu cannot remove.

A display without a notch has no such stop: items may run over the app menus until just past the
app's name, and no single item may be wider than half the screen. There two blank spacers stretch
as well, so both have to sit right of the items to hide, next to the `│`. macOS puts new items at the
far left and keeps positions where smenu cannot write them, so smenu ⌘-drags a stray spacer into
place itself with synthetic mouse events (needs Accessibility; the cursor jumps for a moment). The
app name's width comes from the Split Pills measurement; other capsule styles assume a typical one.
All displays share the same items at the same lengths, so the `│` never outgrows the notch room and
the spacers make up the difference on the other displays.

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
