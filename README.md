# PlayPointer

PlayPointer is a playful macOS screen pointer with a choice of characters and separate modes for controlling the computer and drawing. It is an independent, modified fork of [TinyHand](https://github.com/nilbuild/tinyhand) by Kamran Ahmed; the original MIT license and copyright notice are retained in [LICENSE](LICENSE).

## Status

This is an early source build. It is not an official TinyHand release, does not use TinyHand's update feed, and has not been notarized by Apple. macOS 13 or later is required. Source builds require Xcode and Swift; the build has no external package dependencies. Automatic updates are disabled in this fork.

## Use

- Click the menu-bar icon or press **Control–Option–H** to turn the pointer on or off. If another app uses the shortcut, change it in Settings.
- **Control** mode is the default: click, right-click, drag and scroll in other apps as usual while the pointer remains visible.
- Choose **Draw** on the toolbar, in the menu or in Settings to annotate the screen. Draw needs Accessibility permission. Hold Option temporarily to interact with apps in Draw mode.
- **Escape** clears drawings and hides the pointer; **Control–Option–X** clears drawings. Pick a character on the toolbar or in Settings.

## Build

```sh
./scripts/build-app.sh
```

The result is `dist/PlayPointer.app`, signed ad hoc by default for local development. Ad hoc signing does not establish developer identity or Apple notarization; a different Mac may block the build. Do not bypass Gatekeeper unless you understand and accept the risk. A separately signed and notarized release is not yet available.

## Privacy and permissions

Drawing and interception of clicks use macOS Accessibility access, which gives an app broad ability to control the computer. Grant it only if you trust the build. You can revoke it in System Settings → Privacy & Security → Accessibility. The fork disables the original coordinate and interaction log and does not register itself to start at login automatically. It retains a user-controlled login setting and optional custom-pointer functionality from TinyHand. The latter can open a browser to ChatGPT with the text entered into its prompt. The upstream code also includes optional local image import and clipboard actions.

The source includes upstream graphical assets and code. A source inspection or ad hoc signature is not a security audit, and users should review the exact build they run. This project does not claim an affiliation with the original developer.
