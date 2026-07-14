# Buoy

**Keep any window on top. Really any window.**

Buoy is a free, open-source macOS menu bar utility that keeps any window floating above everything else, and still lets you use it.
Keep your terminal visible while you code in another app, your requirements doc above your editor, or your music player above everything.

<!-- demo GIF goes here before release -->

## Why this exists

macOS has no built-in "always on top".
Worse, it has no public API that lets one app raise another app's window, and the old injection hacks (Afloat) died with modern macOS security.

Buoy takes the honest route instead: it renders a **live mirror** of the window you pick into a floating panel using Apple's ScreenCaptureKit, keeps that panel glued to the real window through the Accessibility API, and hands your clicks straight back to the real window.
The result feels like the real window is always on top, because whenever you interact with it, the real window is what you touch.

## How it works

- **Pin in place** (default): the live mirror locks exactly over the real window and follows it as it moves and resizes.
  Click the mirror and Buoy raises the real window and gets out of the way, so you type and scroll with zero added latency.
  When you focus something else, the mirror pops back on top.
- **Detached float** (hold Option when picking a window): a movable, resizable live thumbnail you can park anywhere.
  Great for keeping an eye on builds, dashboards, or video.
  Supports click-through, remembers its position and opacity per app.
- **Global hotkey**: Option-Command-P pins or unpins whatever window you are using.
- **Per-pin opacity** from the menu bar, live.

## Install

Download the latest `Buoy.dmg` from [Releases](../../releases), open it, and drag Buoy to Applications.

Buoy is free and unsigned (no 99 dollar Apple Developer account behind it), so the first launch needs one extra step:

1. Open Buoy. macOS will block it.
2. Go to **System Settings -> Privacy & Security**, scroll down, and click **Open Anyway**.

Or, if you prefer the terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Buoy.app
```

### Permissions

| Permission | Needed for | When asked |
|---|---|---|
| Screen Recording | The live mirror (it is a window capture) | First launch |
| Accessibility | Pin in place: following and raising the real window | First pin in place |

Detached floats work with Screen Recording alone.
Nothing leaves your Mac; Buoy has no network access, no analytics, no accounts.

Two macOS realities worth knowing up front:

- macOS periodically re-asks you to confirm screen-capture apps. That is a system policy for all such apps, not a Buoy bug.
- Because releases are unsigned, macOS treats each update as a new app and will re-ask for Screen Recording after you update.

## Limitations

- A pinned mirror cannot float above another app's native fullscreen Space. That boundary is enforced by macOS itself.
- DRM-protected video (for example streaming apps with protected playback) captures as a black rectangle.

## Build from source

Requires Xcode 16 or later.

```sh
git clone https://github.com/maokner/Buoy.git
cd Buoy
xcodebuild -project Buoy.xcodeproj -scheme Buoy -configuration Release build
```

For regular local use, install a stable signed copy instead of launching a new ad hoc build from DerivedData each time.
This keeps macOS Screen Recording and Accessibility grants attached to the same application identity across rebuilds.

```sh
./scripts/install-local.sh
open /Applications/Buoy.app
```

The installer uses the first Apple Development signing identity available in your login keychain.
You can create a free personal development identity by signing into Xcode with an Apple Account.

For E2E diagnostics, launch the installed build with its accessible control window.
This window drives the same production capture and pinning managers as the menu bar interface.

```sh
open -na /Applications/Buoy.app --args --control-window
```

## Credits

The mirror-overlay technique was pioneered in the open-source community; [PinWindow](https://github.com/justwy/PinWindow) (MIT) and [Topit](https://github.com/lihaoyun6/Topit) validated the approach.
Buoy is an independent implementation with its own interaction model.

## License

[MIT](LICENSE)
