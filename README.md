# KeepAwake

A tiny macOS menu-bar app that keeps your Mac awake during long waits (like
AI agent runs), and optionally simulates small mouse + keyboard activity so
apps like Slack keep showing you as active.

It's a single coffee-cup icon in the menu bar — no window, no Dock icon.

## Features

- **Keep Awake** — stops the Mac and display from sleeping (on/off, or for a
  set time: 30 min, 1h, 2h, 4h, 8h).
- **Simulate Activity** — after 1 minute of no input, nudges the mouse a few
  pixels and taps Shift (which types nothing). Turns on together with Keep
  Awake. Can be switched off under **Options** if you want keep-awake only.
- Remembers your Simulate Activity preference between launches.

## Requirements

- macOS 11 or later
- Apple's Command Line Tools (for the Swift compiler):
  ```bash
  xcode-select --install
  ```

## Install

```bash
git clone https://github.com/<your-username>/KeepAwake.git
cd KeepAwake
bash build.sh
mv KeepAwake.app /Applications/
```

Then open **KeepAwake** from your Applications folder. The coffee-cup icon
appears in the menu bar.

The first time you turn it on, macOS will ask for **Accessibility** permission
(needed for the Simulate Activity feature). Enable **KeepAwake** under
**System Settings → Privacy & Security → Accessibility**, then turn it on again.
Keep Awake itself works without that permission.

> **Note on the permission prompt:** the build is ad-hoc signed, so each time
> you rebuild the app, macOS may ask for Accessibility permission again. Just
> re-grant it — it takes a few seconds. (A stable code-signing certificate can
> avoid this, but isn't needed for personal use.)

## Start automatically at login (optional)

**System Settings → General → Login Items → +**, then add KeepAwake.

## Settings you can tweak

Near the top of `main.swift`:

- `idleThreshold` — seconds of no input before activity is simulated (default 60)
- `checkInterval` — how often it checks idle time (default 15)
- `nudgePixels` — how far the mouse nudges (default 3)

Change these, then re-run `bash build.sh`.

## Files

- `main.swift` — the whole app
- `build.sh` — compiles, bundles, and signs it into `KeepAwake.app`

## License

MIT — see [LICENSE](LICENSE).
