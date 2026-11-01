# Refiner

A macOS menu-bar app that uses Claude to help with any text you select.

- **Text you're writing** (an email, a message, a form): select it, then click the ✨ **Refine** button that appears, or press **⌥⌘R**. Pick a style (Improve, Grammar, Shorter, Formal, Casual, Simplify), and Claude suggests up to three rewrites (set how many in Settings). **Use** (⌘1–3) puts one in place of your selection.
- **Text you're reading** (a web page, an email you received, a document): select it and click ✨ **Simplify**, or press **⌥⌘R**. Choose Simplify, Summarize or Explain to get one easy-to-read version you can copy.

Settings has your API key, which Claude model to use, the text size, and whether the ✨ button appears.

## Build & run

```sh
./build.sh
open build/Refiner.app
```

On first launch:
1. Grant **Accessibility** access (System Settings → Privacy & Security → Accessibility).
2. Paste your Anthropic API key into Settings. It's stored in the Keychain.

Ad-hoc signed builds lose the Accessibility permission on every rebuild. Sign with a real certificate to keep it:
`SIGN_IDENTITY="Apple Development: you@example.com" ./build.sh`

## Distribution

Refiner can't be sold in the Mac App Store. App Store apps must run in Apple's sandbox, which blocks the Accessibility features Refiner needs to read and replace text in other apps. Distribute it directly instead, in one of two ways.

### Option 1: Share the app as-is (free, for a few people you trust)

Build it and zip it:

```sh
./build.sh
ditto -c -k --keepParent build/Refiner.app Refiner.zip
```

Send `Refiner.zip` by AirDrop, a shared drive or a USB stick.

This build is only *ad-hoc signed*, so macOS blocks it the first time it's opened on another Mac. To install it there:

1. Unzip `Refiner.zip` and drag `Refiner.app` into **Applications**.
2. Double-click it. When macOS says it can't verify the developer, click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the Refiner message, then confirm.

   Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Refiner.app`

`./build.sh` builds one app that runs on both Apple Silicon and Intel Macs, on macOS 14 (Sonoma) or later, including macOS 15 (Sequoia).

### Option 2: Sign and notarize (for anyone, needs an Apple Developer account)

With an [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year), the app opens on any Mac with no warning.

1. **Create a certificate.** In Xcode → Settings → Accounts → Manage Certificates, add a **Developer ID Application** certificate.

2. **Build** (for both Apple Silicon and Intel Macs):

   ```sh
   ./build.sh
   ```

3. **Sign** with the hardened runtime that notarization requires:

   ```sh
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: Your Name (TEAMID)" build/Refiner.app
   ```

4. **Notarize** (Apple's automated malware check), then staple the result to the app:

   ```sh
   # One time only: saves your credentials. Create an app-specific password at appleid.apple.com.
   xcrun notarytool store-credentials refiner --apple-id you@example.com --team-id TEAMID

   ditto -c -k --keepParent build/Refiner.app Refiner.zip
   xcrun notarytool submit Refiner.zip --keychain-profile refiner --wait
   xcrun stapler staple build/Refiner.app
   ```

5. **Package** the stapled app as a disk image:

   ```sh
   hdiutil create -volname Refiner -srcfolder build/Refiner.app -ov -format UDZO Refiner.dmg
   ```

To install, users open `Refiner.dmg` and drag Refiner into **Applications**.

### What every user needs

- **macOS 14 (Sonoma) or later.**
- **Accessibility access.** On first launch, allow Refiner in System Settings → Privacy & Security → Accessibility.
- **Their own Anthropic API key** from [console.anthropic.com](https://console.anthropic.com), pasted into Refiner's Settings. Every refine is billed to the key's account, so don't share your own key.

## How it works

Refiner does four things, in order:

```
1. Notice        2. Read           3. Ask Claude       4. Put it back
you selected  →  the selected  →   for a rewrite   →   in place of your
some text        text              or explanation      selection (or copy it)
```

1. **Notice.** Each time you release the mouse or a key in another app, Refiner checks whether any text is selected. If so, a small ✨ button appears next to it. Pressing ⌥⌘R skips this step.
2. **Read.** Refiner reads the selected text through **Accessibility**, the macOS feature that lets assistive tools read other apps' screens. That's why it needs Accessibility permission. It also checks whether the text can be edited, which decides between **Refine** and **Simplify**. Password fields are always skipped. Where an app doesn't share its selection (such as text on a Chrome page), the hotkey copies it with ⌘C instead and then puts your clipboard back.
3. **Ask Claude.** The text and the style you picked go to the Claude API, which returns one to three rewrites for your own writing (3 by default) or one version for reading.
4. **Put it back.** **Use** replaces your selection with the rewrite. In browsers such as Chrome, where that's unreliable, Refiner pastes the rewrite instead and then restores your clipboard. Read-only text is never changed: you just copy the result.

### Where each part lives

All the app code is in `Sources/Refiner/`:

| File | What it does |
|---|---|
| `main.swift` | Starts the app as a menu-bar app, with no Dock icon. |
| `AppDelegate.swift` | The coordinator. Sets up the ✨ menu-bar menu and the ⌥⌘R hotkey, and connects all the other parts. |
| `SelectionMonitor.swift` | **Step 1.** Watches your clicks and key presses in other apps and reports when text is selected. |
| `Accessibility.swift` | **Steps 2 and 4.** Reads the selection, checks whether it's editable, and writes the result back. Also handles the copy and paste fallbacks. |
| `ClaudeClient.swift` | **Step 3.** The styles (Improve, Simplify…), the instructions sent to Claude, the model list, and the call to the Claude API. |
| `Panels.swift` | What you see: the floating ✨ button and the Refine panel with its suggestions. |
| `Settings.swift` | The Settings window, and saving your choices. The API key goes in the macOS Keychain. |
| `HotKey.swift` | Registers the ⌥⌘R shortcut so it works in any app. |

Other files:

| File | What it does |
|---|---|
| `build.sh` | Builds `build/Refiner.app`. |
| `Package.swift` | Tells Swift how to build the project. |
| `Resources/Info.plist` | The app's name, ID, and the setting that hides it from the Dock. |
| `Resources/AppIcon.*` | The app icon. Regenerate it with `./Scripts/make_icon.sh` after editing `Scripts/make_icon.swift`. |

### Common changes

- **Add or change a style:** edit `RefineMode` in `ClaudeClient.swift`. `title` is the button label, `goal` is what Claude is asked to do, and the `editing` and `reading` lists control where it appears.
- **Change how Claude writes:** edit `systemPrompt` in `ClaudeClient.swift`.
- **Change the hotkey:** edit the `HotKey(...)` line in `AppDelegate.swift`.
- **Add a model:** add a case to `ClaudeModel` in `ClaudeClient.swift`.



I'd like to build an app that can refine my writing or any text I select.

This may not always work properly. Please leave your feedback in the comments or send me an email. Thanks!
