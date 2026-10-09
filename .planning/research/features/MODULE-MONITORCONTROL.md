# Module research: MonitorControl replacement

Researched 2026-10-09 (web + upstream source files, no code changes). Confidence markers: [V] verified in a primary source, [U] uncertain / from memory or a secondary summary.

## 1. Identity, version, licence, maintenance
- Repo: https://github.com/MonitorControl/MonitorControl, about 34k stars, not archived [V, GitHub API].
- Licence: MIT [V, GitHub API licence field `mit`; README says "Completely FREE"]. Compatible with GPL-3.0 as an inspiration or reference source, but copying code needs the MIT notice kept.
- Latest release: v4.4.0, 2026-09-15 [V, https://github.com/MonitorControl/MonitorControl/releases]. Release text: maintenance update for macOS 27 "Golden Gate" and macOS 26 Tahoe, restored the traditional OSD on 26 and 27, fixed Settings window popping up on every macOS 27 Siri interaction, fixed custom shortcut recording on macOS 27. It says "if you need more features please consider switching to BetterDisplay".
- Previous: v4.3.3 (2024-10-04), v4.3.2 (2024-10-02, Sequoia fix), v4.2.0 (2023-09). Two-year release gap before 4.4.0. Last push to repo 2026-09-26 [V].
- Maintenance status: maintenance mode. The maintainer (@waydabber) also makes the commercial-ish BetterDisplay and steers users there. 27 open issues [V, API count, includes PRs].
- Min macOS: 11 fully (10.15 limited) [V README]. v4.4.0 required for macOS 27 [V README].

## 2. Feature list (README, https://github.com/MonitorControl/MonitorControl#major-features) [V]
- Brightness, contrast and volume for external displays. Contrast and volume are DDC only.
- Native OSD (brightness/volume) shown like system keys.
- Four brightness protocols: DDC/CI (external), native Apple protocol (Apple and built-in displays), gamma-table software dimming, "shade" overlay for AirPlay, Sidecar, DisplayLink and other virtual screens.
- Smooth brightness transitions.
- Combined hardware + software dimming, so dimming goes below the display's minimum backlight; dimming to full black.
- Sync brightness from built-in/Apple display (ambient light sensor, Touch Bar changes) to non-Apple externals.
- Sync all displays with one slider or shortcuts.
- Keys: native Apple brightness/volume/mute media keys, or custom keyboard shortcuts. Brightness key goes to the display under the mouse pointer (setting "depends on mouse position"; issues about this on Tahoe were reported and closed).
- Menu bar sliders UI, many advanced settings (DDC polling mode, read delay, per-display overrides, multiple displays, hide menu icon).
- Mute audio device on sync, audio output matching via SimplyCoreAudio (volume of the audio device that belongs to the display).
- Auto-update via Sparkle, localized in many languages.
- HDR: no HDR/XDR upscaling (that is BetterDisplay). v4.3.2 only fixed volume control not being available while a display is in HDR mode [V release notes].

## 3. Permissions and runtime footprint
- Accessibility permission only for media keys (event tap) [V README step 4]. Not needed for sliders and custom shortcuts.
- Not sandboxed; hardened runtime on [V pbxproj]. Menu bar agent (`LSUIElement`) [V Info.plist].
- Network: Sparkle appcast `https://monitorcontrol.app/appcast2.xml` [V Info.plist]. holzBar must NOT include this (no network principle). Dependencies: SimplyCoreAudio, MediaKeyTap (own fork), sindresorhus/Settings, Sparkle [V pbxproj]. Third-party packages are banned in holzBar, so all four need native replacements.

## 4. How it works technically (source: https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/Arm64DDC.swift and Bridging-Header.h) [V]
- Apple Silicon DDC: finds `DCPAVServiceProxy` entries in the IORegistry, matches them to displays via framebuffer/EDID data, creates an `IOAVService` with `IOAVServiceCreateWithService`, then sends MCCS/DDC packets with `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` (chip address 0x37). Retries and sleep timings are configurable.
- Intel: classic IOI2C / IOFramebuffer path (`IOI2CInterface.h`, public IOKit header, but the framebuffer route is deprecated and not available on Apple Silicon).
- Private/undocumented symbols declared by hand in the bridging header:
  - `IOAVServiceCreate`, `IOAVServiceCreateWithService`, `IOAVServiceReadI2C`, `IOAVServiceWriteI2C` (private IOKit)
  - `CoreDisplay_DisplayCreateInfoDictionary` (private CoreDisplay)
  - `DisplayServicesGetBrightness` / `SetBrightness` / `GetLinearBrightness` / `SetLinearBrightness` (private DisplayServices, used for Apple and built-in displays)
  - `CGSServiceForDisplayNumber`, `CGSIsHDREnabled`, `CGSIsHDRSupported` (private CoreGraphics SPI)
  - `OSDManager` / `OSDUIHelperProtocol` (private OSDUIHelper XPC) to show the native OSD. This is what broke on Tahoe; 4.4.0 "restored the traditional OSD" and README still warns the Tahoe OSD percentage may not show/update.
- Media keys: CGEventTap via MediaKeyTap fork; needs Accessibility (`AXIsProcessTrustedWithOptions`).
- Software dimming: gamma table (`CGSetDisplayTransferByTable`-style, public CoreGraphics API, but "gamma activity enforcer" hack because macOS resets tables) and overlay "shade" windows for virtual displays.

## 5. macOS 26 / 27 behaviour and known problems
- macOS 26: native OSD percentage not shown/updated even though the Control Center OSD appears [V README]. Many Tahoe issues were filed and closed (crash on launch, laggy DDC, volume control stopped, brightness meter empty/not current, OSD slider missing, menu icon "always hide" ignored, app stopped working on 26.4) [secondary: GitHub issue search summary, https://github.com/MonitorControl/MonitorControl/issues?q=tahoe, treat titles as V, details U]. Still open: external keyboard sometimes does not trigger, volume control does not work.
- macOS 27: needs v4.4.0; Siri app caused Settings to open, shortcut recording fixed [V release notes]. I found no deeper 27 reports [U; coverage of 27 is thin].
- HDMI: built-in HDMI of 2018 Intel mini, all M1 Macs (MBP 14/16, mini, Studio) and entry M2 mini has no DDC; USB-C/DisplayPort works [V README]. Upstream notes M2 Pro/Max in the troubleshooting wiki as not supported, but v4.2.0 added "DDC support for high-end M2" [V]. The two statements conflict; wiki appears stale [U].
- DisplayLink docks/dongles: no DDC on macOS, software shade only [V README].
- Studio Display / Apple displays: driven through private DisplayServices, not DDC [V source AppleDisplay.swift]. I found no Studio Display-specific bug in sources [U].
- EIZO and others using MCCS over USB or proprietary protocol: software dimming only [V].
- General: DDC is monitor-firmware dependent (brightness works, volume often not), DisplayPort better than HDMI [V wiki https://github.com/MonitorControl/MonitorControl/wiki/Monitor-Troubleshooting]. Flicker/black-screen on some monitors with aggressive polling.
- Sequoia history: v4.2.0 crashes on 15.x when changing brightness on Apple/HDR displays [V release note].

## 6. Alternatives (reference only)
- BetterDisplay (https://github.com/waydabber/BetterDisplay, https://betterdisplay.pro): same maintainer; closed source app; DDC free for personal use, Pro about 21.99 USD / 19.99 EUR perpetual, 14-day trial [V search result https://betterdisplay.pro/]. Adds XDR/HDR upscaling, HDMI DDC on M1, virtual displays/dummies, resolution management.
- Lunar (Alin Panaitiu, https://lunar.fyi): DDC, Sub-zero dimming, sensor/location-based adaptive brightness, per-app presets, XDR; freemium with paid Pro, per MonitorControl wiki "free with daily adjustment limits" [V wiki]; rest of the Lunar details from memory [U, search did not return its site].
- m1ddc / ddcctl: CLI tools, same private IOAVService approach [V wiki mention].
- Other: Apple's own Control Center slider covers Apple displays only.

## 7. Public-API-only vs private-API analysis for holzBar
holzBar principle: never use deprecated/private API, no network, least privilege, no third-party packages.

| Capability | Public API possible? | Notes |
|---|---|---|
| DDC/CI brightness, contrast, volume on Apple Silicon | No | Only via private `IOAVService*`. No public replacement on macOS 26/27 known [U: verify against SDK headers]. |
| DDC on Intel | Not on macOS 26+ (Intel support for 26 is the last gen; IOI2C route deprecated) | Out of scope: macOS 26/27 supports few Intel Macs. |
| Apple/built-in display brightness | No public set API | `DisplayServices*` private. Read-only brightness is also private. |
| Software dimming (gamma) | Mostly | `CGSetDisplayTransferByTable` / `CGDisplaySetDisplayTransferByFormula` public in CoreGraphics (not deprecated). macOS may reset tables on display change/sleep, needs re-apply on `CGDisplayRegisterReconfigurationCallback` and wake notifications. No enforcer hack needed if re-applied. |
| Overlay dimming (shade) | Yes | Borderless click-through NSWindow above all with black alpha; public AppKit. Works on all displays incl. DisplayLink/AirPlay. Caveat: does not reduce backlight, and screenshots/full-screen/Spaces handling needs care. |
| Dim below minimum | Yes (gamma or overlay) | Combine with hardware only if DDC is available, which is private. |
| Media/brightness keys | Partly | `CGEventTap` public but triggers Accessibility/Input Monitoring permission prompt; `NSEvent.addGlobalMonitor` cannot see system-defined keys reliably [U]. Custom hotkeys via Carbon `RegisterEventHotKey` (public, no permission) is the least privilege route. Swallowing the native brightness keys needs the event tap. |
| Native OSD | No | OSDUIHelper is private. holzBar should draw its own HUD window or use a notification-style panel. |
| Detecting displays, EDID name/serial | Yes | `NSScreen`, `CGDisplay*`, `IODisplayCreateInfoDictionary` (public but deprecated-ish [U]; `CGDisplayVendorNumber` etc. fine). |
| HDR/XDR brightness upscaling | No safe route | Hacks with EDR overlays are possible with public `CAMetalLayer`/EDR APIs [U], fragile, out of scope. |
| Per-display volume | Partly | CoreAudio public (`AudioObject*`) for the audio device of an HDMI/DP display, only if it exposes a volume control; DDC volume would be private. |
| Auto-update, network | n/a | holzBar must not copy Sparkle. |

## 8. Recommendation for the holzBar module
- A "pure public API" module can honestly offer: software dimming (gamma and/or overlay), per-display slider, below-minimum dimming, own HUD, Carbon hotkeys, and audio-device volume. This covers DisplayLink, AirPlay, Sidecar, TVs and HDMI-on-M1 cases that MonitorControl cannot do with hardware anyway.
- It cannot replace MonitorControl's core value (real backlight/DDC control and Apple display brightness) without private API (`IOAVService*`, `DisplayServices*`). Decide explicitly: either ship as "software dimming module" and label clearly that hardware brightness stays with MonitorControl/BetterDisplay, or grant a documented, isolated exception. Recommendation: do not grant the exception; the private APIs have already broken repeatedly on every major macOS release (Sequoia crash, Tahoe OSD).
- Permissions for the public module: none for sliders and Carbon hotkeys; Accessibility only if the user opts into capturing native brightness keys.
- Open questions to verify with a real SDK check: whether any public DDC path exists in the 26.x/27 SDK; whether gamma tables survive display sleep on 26/27 without re-apply; whether overlay windows are captured by screenshots.

## Sources
- https://github.com/MonitorControl/MonitorControl (README, release notes, Arm64DDC.swift, Bridging-Header.h, AppleDisplay.swift, Info.plist, project.pbxproj via raw.githubusercontent.com)
- https://github.com/MonitorControl/MonitorControl/releases
- https://github.com/MonitorControl/MonitorControl/wiki/Monitor-Troubleshooting
- https://github.com/MonitorControl/MonitorControl/issues?q=tahoe (summary only)
- https://betterdisplay.pro/ , https://github.com/waydabber/BetterDisplay
