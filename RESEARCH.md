# Notes on the upstream macOS build

This fork started from the public TinyHand source at commit `c5fb36b7c4d7c87480958872a724b30a52427a47` and a focused examination of the installed TinyHand 1.0.2 executable. The original project is [nilbuild/tinyhand](https://github.com/nilbuild/tinyhand).

The universal upstream executable examined had SHA-256 `dfa1ea764d5bb459c3869c4003b8299312a847717e2cfdac116d45561f584408`. Its Apple Developer ID signature and stapled notarization were verified locally. The upstream source and the executable are not proven byte-for-byte equivalent: the examined source commit is newer than the release build.

REA binary inventory and focused disassembly showed a mouse-event tap in the main input path, separate shortcut handling, and the Sparkle updater. The installed build has the upstream GitHub release feed configured. In the source examined, drawing mode intentionally consumes clicks, and upstream diagnostics can write click positions to a local log. The custom-hand feature can open ChatGPT with the user's entered prompt as a URL query. These are focused observations, not a complete malware or privacy audit; absence of a finding does not establish safety.

This fork removes persistent event logging, uses a different bundle identifier, disables automatic updater configuration, avoids first-run login-item registration, and adds a separate control mode. See README for the current build and permission limitations.

REA provided binary inventory and metadata. Its Ghidra analysis of the extracted ARM64 slice timed out; no decompiled pseudocode was obtained. The selected call sites were checked with Xcode disassembly for both architectures. No packet capture or runtime network monitoring was performed.
