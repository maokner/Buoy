# Buoy - Design Spec

Version 0.1.0.
Menu bar utility that keeps any macOS window always on top by rendering a live ScreenCaptureKit mirror in a floating panel.
This document is the source of truth for the user-facing experience.
Strings, SF Symbol names, and ordering are meant to be implemented verbatim.

## 0. Design principles

1. Native first.
Buoy is an `NSMenu` and `NSPanel` app.
It follows the macOS HIG for menus, alerts, and title-case menu items.
Nothing here should feel like a cross-platform toolkit.

2. Zero configuration to first success.
The default shortcut and picker work without setup, there is no account, and shortcut customization stays in one small Settings window.
The path from launch to a floating window is a menu click plus one system permission.

3. Confident, friendly, terse copy.
Model the tone on Raycast and CleanShot: short sentences, plain verbs, no marketing.
No exclamation marks.
No em dashes; use a plain hyphen with spaces around it.

4. The mirror should be honest.
A pinned mirror must never be mistaken for the real window in a way that confuses the user.
It always offers a visible way out (unpin) and a clear signal that it is Buoy.

### Terminology used in UI copy

- "Pin" (verb and noun): the general act of keeping a window on top. A live copy of a window that Buoy is keeping visible.
- "Pin in place": the mode where the mirror locks over the real window and tracks it.
- "Float" / "detached float": the movable, resizable thumbnail mode.
Use "Float" in menu items and "detached float" only in longer explanatory copy.

---

## 1. Menu bar icon

Buoy is a menu-bar-only app (`NSApp.setActivationPolicy(.accessory)`, no Dock icon).
The status item uses the custom Tidemark template image so macOS tints it for light and dark menu bars automatically (`image.isTemplate = true`).

Tidemark is a sphere divided by a horizontal wave-shaped negative-space gap.
Its source geometry is a 21.2 unit diameter circle centered at `(16, 16)` and a cleared 3.2 unit wave stroke following `M2 17.4 q3.5 -3.6 7 0 t7 0 t7 0 t7 0` in a 32 unit canvas.
Render it programmatically at 18pt with antialiasing so it remains crisp at 1x and 2x.

- Idle: show the unmodified split sphere.
- Active: add one small centered solid dot inside the waterline gap.
- Do not use color or a numeric badge.
- `button.toolTip` is `Buoy` when idle and `Buoy - {n} pinned` when active.
- Use the same Tidemark mark in the overlay hover strip and About panel so Buoy has one logo.

---

## 2. Menu structure

The menu is rebuilt on `menuWillOpen` and whenever sessions change.
All items use title case per HIG.
`menu.autoenablesItems = false` stays as-is; disabled rows are informational.

### 2.1 Top-level skeleton (with an active pin and recent windows present)

```
Pin Frontmost Window          ⌥⇧P            [symbol: pin.badge.plus]
Pin a Window...                               [symbol: viewfinder]
Choose from List                     ▸        [symbol: list.bullet.rectangle]
Recent                                        (disabled section header, small)
  Safari - Anthropic                         [symbol: clock]
  Terminal - node                            [symbol: clock]
────────────────────────────────────
Active Pin                                    (disabled section header, small)
  ◆ Figma - Untitled          ▸              [pin submenu, symbol: pin.fill]
────────────────────────────────────
Settings...                                   [symbol: gearshape]
Permissions...                                [symbol: lock.shield]
About Buoy                                     [symbol: info.circle]
Quit Buoy                     ⌘Q
```

Notes on the skeleton:

- Omit the Recent header and rows when none of the persisted identities match a currently available window.
- Show no more than three recents, most recently pinned first.
- The row in "Active Pin" carries a leading SF Symbol that encodes the mode: `pin.fill` for pin-in-place, `rectangle.on.rectangle` for detached float.
- Keep `indentationLevel = 1` on the pin row under the "Active Pin" header.

### 2.2 Item-by-item spec

Order top to bottom.

1. **Pin Frontmost Window** - symbol `pin.badge.plus`. The menu key equivalent always reflects the current saved shortcut. The default is `⌥⇧P`, and the item has no key equivalent when the shortcut is cleared.
2. **Pin a Window...** - symbol `viewfinder`. Closes the menu and enters picker mode (section 2.3).
3. **Choose from List** - symbol `list.bullet.rectangle`. Its submenu contains the existing window list and Option alternates (section 2.3.2).
4. **Recent** - optional disabled header followed by up to three matching windows, newest first. Each row uses `clock` and starts a pin in place.
5. Separator.
6. **Active Pin** - disabled header row followed by the active pin row (section 2.4) or one disabled `None yet` row.
7. Separator.
8. **Settings...** - symbol `gearshape`. Opens the shortcut settings window. Use the standard Command-comma menu equivalent.
9. **Permissions...** - symbol `lock.shield`. Opens the permissions status surface (section 6.4).
10. **About Buoy** - symbol `info.circle`. Opens the standard About panel (section 2.6).
11. **Quit Buoy** - key equivalent `⌘Q`. No symbol.

SF Symbols on menu items are set via `item.image = NSImage(systemSymbolName:accessibilityDescription:)` with `isTemplate = true`.
Use a consistent point size config of `.init(pointSize: 13, weight: .regular)` so all row glyphs align.

### 2.3 Window selection

#### 2.3.1 "Pin a Window..." picker

Picker mode is the primary visual path to first success.
It creates one transparent, borderless, nonactivating overlay panel per connected screen at a high window level.
The panels accept picker mouse events without activating Buoy or moving focus from the current app.

On mouse movement, query `CGWindowListCopyWindowInfo` in front-to-back order and select the first eligible window containing the global pointer location.
Eligible windows are layer 0, on screen, at least 80 by 50 points, visible, and not owned by Buoy.
Convert Quartz top-left frames to Cocoa bottom-left frames using the global primary-screen top, matching `WindowTracker.cocoaFrame`.

Draw a rounded accent-color stroke and faint accent fill over the selected frame.
Show a compact tag near the pointer containing `{App} - {Window Title}` and the exact hint `Click to pin - hold Option to float - Esc to cancel`.
Clamp the tag inside the owning screen.

- A normal click consumes the picker event, tears down all picker panels, requests required permissions, and pins the selected window in place.
- An Option-click consumes the event, tears down all picker panels, and creates a detached float.
- Clicking the empty desktop or pressing Escape cancels and tears down every panel and event monitor.
- Rebuild the per-screen panels when the screen configuration changes.
- Keep the panels on all Spaces and exclude every Buoy-owned window from hit testing.

#### 2.3.2 "Choose from List" submenu

This submenu is rebuilt each time the menu opens, driven by `WindowState`.

Header hint (always the first row, disabled):

```
Hold Option to float instead
```

This replaces the current `Hold Option for a Detached Float`.
It is shorter and uses the verb "float" that appears elsewhere.
Followed by a separator, then the window list.

Window list rows (one primary + one hidden alternate per window):

- Primary row title: `{App} - {Window Title}`, for example `Safari - Anthropic`.
  - Action: pin in place.
  - Leading symbol: none on individual window rows (keeps the list dense and scannable; the app name already anchors each row).
  - If the window is already pinned: `item.state = .on` (checkmark) and `isEnabled = false`, so it reads as "already pinned".
- Alternate row (shown while Option is held): `Float {App} - {Window Title}`.
  - `isAlternate = true`, `keyEquivalentModifierMask = [.option]`.
  - Action: detached float.

Rows appear immediately with their titles.
Populate a live `SCScreenshotManager` thumbnail asynchronously at approximately 44pt high and cache it briefly so opening the menu remains responsive.
Give each thumbnail a subtle adaptive backdrop and hairline border so dark or low-content windows remain recognizable in either menu appearance.

Window titles can be long. Do not truncate manually; let AppKit elide. But cap the app-plus-title string is unnecessary since the menu width handles it.

#### Empty and error states inside the submenu

Exactly one disabled row, no window list:

| Condition | Row text |
|-----------|----------|
| Enumeration in flight | `Loading windows…` |
| Loaded, zero eligible windows, permission granted | `No windows to pin` |
| Screen Recording not granted | `Turn on Screen Recording to pin windows` |
| Enumeration failed | the localized error string from `WindowEnumerationError` |

When the reason is missing Screen Recording, add a second enabled row beneath it:

```
Open Screen Recording Settings…
```

Action: `permissionsManager.openScreenRecordingSettings()`.
This turns a dead end into a one-click fix.
Symbol `arrow.up.forward.app` on that row.

Copy change from current build: `No Available Windows` becomes `No windows to pin`, and `Screen Recording Permission Required` becomes `Turn on Screen Recording to pin windows` (active voice, tells the user what it unlocks).

### 2.4 Active pin submenu

Buoy has at most one active pin across pin-in-place and detached modes.
Pinning a different window first saves and fully stops the current session, then starts the new session.
Choosing the already-pinned window from the picker, list, or Recent is a no-op, while the Pin Frontmost Window shortcut retains its toggle behavior when that pinned window is frontmost.

The active pin row is itself a submenu.
This is where pin controls live, keeping the top level flat.

Row title (the parent item under "Active Pin"): `{App} - {Window Title}`.
Leading symbol: `pin.fill` (pin in place) or `rectangle.on.rectangle` (detached float).

Submenu contents, top to bottom:

```
Opacity                                       (disabled label row)
  [ ●━━━━━━━━━ ]  100%                        (NSSlider as custom view)
────────────────────────────────────
☐ Click-Through                               (detached float only; symbol cursorarrow.rays)
────────────────────────────────────
Show Real Window                              (symbol: arrow.up.left.square)
Unpin                                ⌥⇧U      (symbol: pin.slash)
```

Details:

- **Opacity**: a labeled section. The label row `Opacity` is a small disabled header. Below it, an `NSSlider` embedded as an `NSMenuItem.view` custom view, range 0.15 to 1.0, continuous, bound to `session.opacity`. To the slider's right, a live percentage label (`100%`, `85%`, …) rounded to the nearest 5%. Minimum shown value is `15%` since the model floor is 0.15. The slider view is inset to match menu content margins (leading 21pt to clear the symbol gutter, trailing 14pt).
- **Click-Through**: only present when `mode == .detached`. A checkbox item (`item.state`), symbol `cursorarrow.rays`. When on, the panel sets `ignoresMouseEvents = true` so clicks pass to whatever is behind the float. When off, clicking the float activates the source. Not shown for pin-in-place, where click-through would defeat the mode.
- **Show Real Window**: symbol `arrow.up.left.square`. Raises and focuses the source window (same effect as clicking a pin-in-place mirror). Useful for detached floats too. For a pin-in-place pin this momentarily reveals the native window.
- **Unpin**: symbol `pin.slash`. The menu key equivalent always reflects the current saved unpin shortcut. The default is `⌥⇧U`, and the item has no key equivalent when the shortcut is cleared. Removes the session.

This is a redesign of the current flat `Unpin {mode}: {App} - {Title}` rows.
Moving controls into a per-pin submenu is what allows opacity and click-through to exist without cluttering the top level.

### 2.5 Empty state (no active pin)

Under the `Active Pin` header, a single disabled row indented one level:

```
None yet
```

Softer and more inviting than a bare `None`; implies the user will add some.

### 2.6 About Buoy

Standard AppKit about panel via `NSApplication.orderFrontStandardAboutPanel(options:)`.
Credits string (an `NSAttributedString` under `.credits`):

```
Keeps any window on top with a live mirror.
Free and open source.
```

Include a clickable `github.com/{owner}/Buoy` link in the credits (set as an attributed link).
Version and build come from `Info.plist` automatically.

---

## 3. Overlay panel affordances

The floating panel (`PinOverlayPanel`) hosts the live capture.
The design goal: make it obviously a Buoy pin, keep it out of the way, and always offer a one-click exit.

### 3.1 Persistent chrome

- **Corner radius**: keep the current `9pt` on the content container. Consistent with macOS window rounding at this size.
- **Border**: add a 1pt inner hairline stroke, `NSColor.white.withAlphaComponent(0.12)` over the black container, drawn on the container layer (`borderWidth = 1`, `borderColor`). This subtle edge separates the mirror from whatever is behind it and reads as "a framed copy", not the live window. It is quiet enough to disappear against most content.
- **Shadow**: keep `hasShadow = true`. The system shadow already helps the panel read as a floating object.

### 3.2 Hover controls

Controls are hidden until pointer-over, then fade in over 0.12s.
On mouse exit, fade out over 0.2s.
Use an `NSTrackingArea` on the interaction view.

While hovering, show a top control strip (a thin translucent bar, `NSVisualEffectView`, `.hudWindow` material, ~28pt tall, pinned to the top edge, same corner radius on top corners):

- **Left**: the existing close/unpin button, symbol `xmark.circle.fill`, white, tooltip `Unpin`. Keep at 22x22 at leading 10, top centered in the strip. This is the primary unpin affordance on the panel itself.
- **Center**: a tiny wordmark lockup - the Buoy glyph (section 4.2 menu bar mark) at 12pt plus the source label `{App}` in `NSFont.systemFont(ofSize: 11, weight: .medium)`, white at 0.9 alpha, truncating tail. This is the honest-signal: hovering any pin shows "Buoy - Figma", so it can never be confused for the real window.
- **Right** (detached float only): a drag affordance is unnecessary because the whole float is draggable; instead show `arrow.up.left.square` (Show Real Window) at 16pt, tooltip `Show real window`.

The strip background is `black.withAlphaComponent(0.35)` behind the vibrancy so white glyphs stay legible over bright captures.

At rest (no hover) the panel shows only the live mirror, the hairline border, and the shadow.
No persistent badge - the hairline plus the on-hover wordmark carry the identity without clutter.

### 3.3 Interaction model recap (for affordance context)

- Pin in place: a click anywhere on the mirror body (not on a hover control) raises the real window and hides the mirror. The mirror returns when focus leaves the source. This is the `onInterceptedMouseDown` path.
- Detached float: the body is draggable (move) and resizable (edges). A single click on the body activates the source without hiding the float. Click-through (per-pin submenu) makes the body transparent to clicks.

### 3.4 Stalled / paused capture state

Trigger: no new frame for the stall threshold (current code: source minimized and >0.45s since last frame, or a capture error).

Design intent: hold the last good frame, dim slightly, and show a small "Paused" hint so the user knows the mirror is frozen, not broken.

Visual spec when stalled:

- Keep the last frame visible (do not blank to black).
- Dim to `baseOpacity * 0.78` (already implemented in `setCaptureStalled`). Keep this value.
- Overlay a centered pill: `NSVisualEffectView` `.hudWindow` material, corner radius 8, height 24, horizontal padding 10, containing symbol `pause.fill` (11pt) plus label `Paused` in `.systemFont(ofSize: 11, weight: .medium)`, white.
- The pill fades in after 300ms of stall (so brief hitches never flash it) and fades out immediately when frames resume.
- Do not show error text on the panel. If the capture has hard-failed (not just paused), the session should surface the alert in section 5 and unpin; the panel is not where errors are explained.

Copy: the word on the pill is `Paused`, not `Frozen` or `Stalled` - it implies temporary and recoverable.

---

## 4. Icon direction

### 4.1 App icon (buoy motif)

Concept: a **navigational buoy floating on water**, viewed straight-on, centered in the rounded-rect macOS icon tile.
The buoy doubles as a subtle pin: the buoy's vertical mast reads like a pin's needle from a distance.

Precise composition, to be built as vector layers:

- **Tile**: standard macOS Big Sur rounded rectangle (squircle), full bleed. Background is a top-to-bottom gradient of two blues: top `#2E9BE6` (sky), bottom `#0A5FB0` (deeper water). Subtle, no photographic noise.
- **Water**: bottom ~35% of the tile is water, a slightly darker blue band `#0A4E92` with two thin lighter arcs (`white` at 0.25 and 0.15 alpha) suggesting ripples, centered under the buoy.
- **Buoy body**: a classic can/pillar buoy centered horizontally, sitting so its waterline is at the top of the water band. Body is a vertical capsule, ~40% of tile width. Color split into two horizontal bands: upper `#FF5A47` (warm red-orange), lower `#F2F2F2` (white), a nautical two-tone. A thin dark keel line `#0A3A6E` where it meets the water.
- **Top mast + light**: a short vertical mast rising from the body top, capped with a small circular lamp. The lamp is `#FFC24B` (amber) with a soft outer glow (radial, amber at 0.5 to 0 alpha). This glow is the focal point and reads as "beacon / always visible".
- **Optional flag/highlight**: a single specular highlight down the left edge of the body (`white` at 0.3 alpha, 2pt wide) to give it dimension.
- **Shadow**: a soft elliptical contact shadow on the water directly beneath the buoy, `#062C55` at 0.3 alpha, blurred.

The mnemonic: red-and-white buoy, amber beacon on top, calm blue water.
Simple enough to remain legible at 16pt in the Finder and 1024pt in the App Store style export.
No text in the icon.

Provide all standard `AppIcon.appiconset` sizes (16, 32, 128, 256, 512 at 1x and 2x). Create the asset catalog at `Buoy/Assets.xcassets/AppIcon.appiconset` (none exists yet).

### 4.2 Menu bar template icon and app glyph

The menu bar, hover strip, and About panel use the same programmatically drawn Tidemark geometry specified in section 1.
It is a pure-alpha template image with no baked color.
The active menu-bar variant adds a subtle centered dot in the waterline gap, while the hover strip and About panel use the idle mark.
The AppIcon asset catalog remains unchanged and continues to provide the Finder and application icon.

---

## 5. Error alerts and copy

All alerts use `NSAlert`, `NSApp.activate(ignoringOtherApps: true)` before `runModal`.
Titles are sentence-style but concise; buttons are title case.

### 5.1 Could not pin

Shown when `pinManager.pin` throws (capture failed to start).

- `messageText`: `Could not pin that window`
- `informativeText`: `Buoy could not start a live mirror for this window. It may have closed or blocked screen capture. Try another window.`
- Buttons: `OK`
- Style: `.warning`

(Replaces current `Could Not Pin Window` + raw `error.localizedDescription`. Keep the raw error available in Console logging, not in the user-facing text.)

### 5.2 Source window closed

When `onSourceClosed` fires, unpin silently.
No alert - a window closing is expected and self-explanatory; the pin just disappears.
Do not interrupt the user for this.

### 5.3 Capture failed mid-session (hard error)

If capture errors in a way that is not a recoverable stall (stream ends, source revoked), unpin and, only if the failure was unexpected, show:

- `messageText`: `Lost the connection to that window`
- `informativeText`: `Buoy stopped mirroring because the window is no longer available. Pin it again to bring it back.`
- Buttons: `OK`
- Style: `.warning`

Suppress this alert if the source window was closing anyway (covered by 5.2).

### 5.4 Hotkey could not resolve a frontmost window

When the configured shortcut (or the menu item "Pin Frontmost Window") fires but there is no eligible frontmost window (Buoy's own menu is frontmost, the desktop is focused, or the app has no capturable window):

- `messageText`: `Nothing to pin`
- `informativeText`: `Buoy could not find a window to pin. Click the window you want on top, then use your Pin Frontmost Window shortcut.`
- Buttons: `OK`
- Style: `.informational`

The menu shows the current binding using AppKit's native key-equivalent column.
The default is `⌥⇧P`, but the alert remains correct after customization or clearing.

### 5.5 Already pinned (frontmost)

If the frontmost window is already pinned when the command is invoked, treat it as a toggle: unpin it.
This makes the hotkey a true pin/unpin.
No alert.
This matches the task brief ("pins/unpins the frontmost window").

### 5.6 Dedicated unpin shortcut

The configured Unpin shortcut removes the active pin regardless of which app or window is frontmost.
Its default is `⌥⇧U`.
When there is no active pin, it does nothing and shows no alert.

---

## 6. Permissions and first-run flow

### 6.1 Recommended sequencing

**Recommendation: ask for Screen Recording up front on first launch; ask for Accessibility lazily, only the first time the user starts a pin-in-place pin.**

Justification:

- Screen Recording is required for every feature Buoy has. Nothing works without it, so requesting it immediately (with a plain-language primer first) is honest and gets the one unavoidable permission out of the way. It directly serves the sub-30-second goal: grant once, then every window is pinnable.
- Accessibility is only needed by pin-in-place (to raise and track the real window). Detached floats never need it. Asking for it up front would be requesting a scary permission the user may never use, which hurts trust and conversion. Requesting it at the exact moment of first pin-in-place ties the ask to a concrete action the user just took, which is the pattern Apple recommends and which Raycast/CleanShot follow.
- Net effect: a user who only ever floats windows is never asked for Accessibility. A user who pins in place is asked once, in context, and understands why.

This matches the current code shape: `offerFirstLaunchScreenRecordingSetup()` on launch, `ensureAccessibilityAccess()` gated inside `pinWindow`. The changes below are copy and flow polish, not a re-architecture.

### 6.2 First-run flow, step by step

1. **Launch.** No window appears. The Tidemark mark shows in the menu bar. The app is `.accessory`, so no Dock icon, no app switcher entry.
2. **Screen Recording primer** fires immediately (`offerFirstLaunchScreenRecordingSetup`), but only if not already granted and not previously offered.
   - Title: `Let Buoy see your windows`
   - Body: `Buoy floats a live copy of any window you pick. To do that, macOS needs to grant Screen Recording. Buoy only mirrors the windows you choose, and nothing leaves your Mac.`
   - Buttons: `Continue` (default) / `Not Now`
   - On `Continue`: call `CGRequestScreenCaptureAccess()`, which triggers the real system prompt.
3. **If granted**: no further interruption. The user opens the menu, picks a window, it floats. Target: under 30 seconds from launch.
4. **If denied or the system prompt cannot show** (already-denied state): show the settings fallback:
   - Title: `Screen Recording is off`
   - Body: `Turn on Buoy under Privacy & Security, Screen Recording. macOS may ask you to quit and reopen Buoy once you do.`
   - Buttons: `Open Settings` (default) / `Later`
   - `Open Settings` deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
5. **User picks a window** with the picker, a Recent row, or Choose from List.
   - A normal click requests pin in place. On the first attempt, the **Accessibility primer** fires now (section 6.3).
   - An Option-click in the picker or list requests Float. No Accessibility permission is needed.
6. **Live float appears.** First success.

### 6.3 Accessibility primer (lazy, on first pin-in-place)

Shown by `ensureAccessibilityAccess()` the first time a pin-in-place is attempted without the permission.

- Title: `Buoy needs one more thing to pin in place`
- Body: `Pinning in place lets Buoy raise and follow the real window as it moves. That needs Accessibility access. Floating windows do not - if you would rather not grant this, hold Option when picking a window to float it instead.`
- Buttons: `Open Settings` (default) / `Not Now`
- On `Open Settings`: call `AXIsProcessTrustedWithOptions([prompt: true])` (surfaces the system prompt), and if still untrusted, deep-link to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- On `Not Now`: abort the pin quietly. Do not fall back to a float automatically; the user chose an explicit action and a surprise mode-switch would be worse. The Option-to-float hint in the body teaches the alternative.

The body's mention of the Option-to-float escape hatch is important: it turns a permission wall into a choice and preserves zero-config success for the privacy-conscious.

### 6.4 Permissions status surface (menu item "Permissions...")

Replaces the current three-button alert with a clearer status read-out.

- Title: `Buoy Permissions`
- Body (two lines, each with a status):
  ```
  Screen Recording - {Granted / Not granted}. Required to mirror any window.
  Accessibility - {Granted / Not granted}. Needed only for Pin in Place.
  ```
- Buttons depend on what is missing, choosing the most useful default:
  - If Screen Recording missing: `Open Screen Recording` (default) / `Open Accessibility` / `Done`.
  - Else if Accessibility missing: `Open Accessibility` (default) / `Open Screen Recording` / `Done`.
  - If both granted: single `Done` button, and the body ends with a line `Everything Buoy needs is enabled.`
- Each `Open …` button deep-links to the matching Settings pane.

Copy change: drop the current line `Accessibility is not needed yet, but will support window tracking in a later phase.` It is stale (tracking is live) and hedgy.

### 6.5 Discoverability hint (Option to float)

Three placements teach the same gesture in context:

1. The picker tag says `Click to pin - hold Option to float - Esc to cancel`.
2. The Choose from List submenu header says `Hold Option to float instead`.
3. The Accessibility primer explains that holding Option floats without Accessibility access.

Do not add a separate onboarding coach mark.

### 6.6 Shortcut settings

`Settings...` opens a small regular window titled `Buoy Settings` and activates Buoy.
It contains native shortcut recorder rows for `Pin frontmost` and `Unpin`, each with `Reset to Default` and `Clear` buttons.
The defaults are Option-Shift-P and Option-Shift-U.
When armed, the recorder captures the next key-down event containing at least one modifier and displays standard symbols such as `⌥⇧P` or `⌃⇧K`.
Escape cancels recording, `Clear` disables that global shortcut, and `Reset to Default` restores that row's default.
The two shortcuts cannot use the same key and modifier combination.
When a recording conflicts, Buoy keeps the old value and shows a brief validation message.
Changes persist immediately and re-register both Carbon hotkeys without relaunching.
The status menu and control window update from the same persisted bindings.

---

## 7. Copy sheet (quick reference)

Menu items:

- `Pin Frontmost Window`
- `Pin a Window...`
- `Choose from List`
- `Recent`
- `Hold Option to float instead`
- `{App} - {Window Title}`
- `Float {App} - {Window Title}`
- `Active Pin`
- `None yet`
- `Settings...`
- `Permissions...`
- `About Buoy`
- `Quit Buoy`

Per-pin submenu:

- `Opacity`
- `Click-Through`
- `Show Real Window`
- `Unpin`

Submenu empty/error states:

- `Loading windows…`
- `No windows to pin`
- `Turn on Screen Recording to pin windows`
- `Open Screen Recording Settings…`

Picker:

- `Click to pin - hold Option to float - Esc to cancel`

Settings:

- `Buoy Settings`
- `Keyboard Shortcuts`
- `Pin frontmost`
- `Unpin`
- `Click a field, then press a shortcut. Clear disables that shortcut.`
- `Type Shortcut`
- `Reset to Default`
- `Clear`

Panel:

- `Unpin` (tooltip)
- `Show real window` (tooltip)
- `Paused` (stall pill)
- Hover wordmark: `Buoy - {App}`

Permissions:

- Primer title: `Let Buoy see your windows`
- Primer body: `Buoy floats a live copy of any window you pick. To do that, macOS needs to grant Screen Recording. Buoy only mirrors the windows you choose, and nothing leaves your Mac.`
- Denied title: `Screen Recording is off`
- Denied body: `Turn on Buoy under Privacy & Security, Screen Recording. macOS may ask you to quit and reopen Buoy once you do.`
- Accessibility title: `Buoy needs one more thing to pin in place`
- Accessibility body: `Pinning in place lets Buoy raise and follow the real window as it moves. That needs Accessibility access. Floating windows do not - if you would rather not grant this, hold Option when picking a window to float it instead.`

Errors:

- `Could not pin that window` / `Buoy could not start a live mirror for this window. It may have closed or blocked screen capture. Try another window.`
- `Lost the connection to that window` / `Buoy stopped mirroring because the window is no longer available. Pin it again to bring it back.`
- `Nothing to pin` / `Buoy could not find a window to pin. Click the window you want on top, then use your Pin Frontmost Window shortcut.`

Buttons: `Continue`, `Not Now`, `Open Settings`, `Later`, `Open Screen Recording`, `Open Accessibility`, `Done`, `OK`.

---

## 8. Design rationale and tradeoffs

- **Tidemark active dot over a badge.** A colored badge or count would be louder than a native menu extra. One small dot in the negative-space waterline emphasizes the custom mark without changing its silhouette, and the tooltip carries the count.
- **Picker before a long window list.** Pointing at a visible window is faster than recognizing it in a text menu. The list remains available for keyboard and title-driven selection, while thumbnails reduce ambiguity.
- **Per-pin submenu vs flat rows.** The current build lists each pin as a single flat "Unpin …" row. That has no room for opacity or click-through. Nesting controls in a per-pin submenu keeps the top level to one line per pin while unlocking the per-pin opacity and detached-only click-through the product promises. Tradeoff: one extra hover to reach unpin, mitigated by keeping the panel's own close button as the fast path.
- **Lazy Accessibility, eager Screen Recording.** Detailed in 6.1. The core bet: never ask for a permission a given user will not use. This protects trust and keeps the pure-float path truly single-permission.
- **Honest mirror via hover wordmark, not a persistent badge.** A permanent "Buoy" badge on every pin would be visual noise on a tool whose whole point is an unobtrusive floating copy. The hairline border gives a constant quiet signal; the hover wordmark gives an explicit one on demand. Tradeoff: at rest there is no literal label, but the border plus the fact that the user just created the pin makes misidentification unlikely, and hover resolves any doubt.
- **"Paused" over "Frozen".** When capture stalls (commonly a minimized source), the last frame plus a soft "Paused" pill communicates "temporary, will resume" rather than "broken". Dimming reinforces "not live" without hiding useful context.
- **One focused Settings window.** Pin controls stay with the active pin, while the two global shortcuts live in a small dedicated window. Useful defaults mean users never need to open it.
- **One pin at a time.** A single active pin keeps the menu predictable and makes the global Unpin shortcut deterministic. Replacement stops the old capture before starting the new one, so capture and tracking resources never overlap.
- **Option-to-float taught in-context.** Rather than an onboarding tour, the one non-obvious gesture is surfaced exactly where and when it matters: the submenu header and the Accessibility wall. This respects the terse, native ethos and avoids modal onboarding.
