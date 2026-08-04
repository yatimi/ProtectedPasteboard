# ProtectedPasteboard

A policy-driven pasteboard security library for banking, crypto, and privacy-sensitive iOS apps.

`ProtectedPasteboard` turns security decisions such as scope, expiration, Universal Clipboard, payload limits, and allowed types into explicit, testable Swift values. It does **not** claim that the system pasteboard is a secure storage mechanism.

## Why

Sensitive applications commonly need more than `UIPasteboard.general.string = value`:

- wallet addresses and bank identifiers may need controlled cross-app copying;
- one-time codes should expire quickly and remain on the current device;
- internal values should stay on a nonpersistent app pasteboard;
- seed phrases, private keys, PINs, and CVVs should never enter a pasteboard;
- passive pasteboard reads should not happen without user intent;
- delayed cleanup must not delete content the user copied afterward.

## Requirements

- Swift 6.2+
- iOS 15+
- Xcode 26+

The policy engine is platform-neutral enough to test on macOS. The production adapter currently targets UIKit.

## Installation

Add the package URL in Xcode or declare it in `Package.swift`:

```swift
.package(url: "https://github.com/yatimi/ProtectedPasteboard", from: "0.1.0")
```

Then add `ProtectedPasteboard` to your target dependencies.

## Quick start

Use the app-wide production facade:

```swift
import ProtectedPasteboard

@MainActor
let pasteboard = ProtectedPasteboard.shared
```

Copy a financial identifier with conservative defaults:

```swift
let receipt = try pasteboard.write(
    "DE89 3704 0044 0532 0130 00",
    policy: .sensitive
)
```

The `.sensitive` policy disables Universal Clipboard, limits the content to text or URLs, caps its size, and requests removal after 60 seconds.

Copy a one-time code:

```swift
try pasteboard.write("481920", policy: .oneTimeCode)
```

Use the nonpersistent app pasteboard for in-app workflows:

```swift
try pasteboard.write("internal value", policy: .appPasteboard)
```

Prohibit copying a secret:

```swift
let seedPhrasePolicy = PasteboardPolicy.prohibited(
    reason: "Seed phrases must never enter a pasteboard."
)

try pasteboard.write(seedPhrase, policy: seedPhrasePolicy)
```

Read only after an explicit user action:

```swift
let value = try pasteboard.readStringAfterUserAction()
```

Read one explicitly requested representation instead of decoding everything on
the pasteboard:

```swift
let imageData = try pasteboard.readDataAfterUserAction(
    ofExactType: .png,
    maximumByteCount: 5 * 1_024 * 1_024
)
```

The limit prevents oversized data from propagating through the application,
although UIKit may materialize provider-backed data before the library can
measure it.

Inspect types without intentionally decoding the payload:

```swift
let snapshot = pasteboard.inspect()
```

Check metadata before offering a paste action:

```swift
if pasteboard.advertisesContent(conformingTo: .url) {
    // Present a user-initiated Paste URL action.
}
```

Advertised metadata does not guarantee that a provider-backed payload will load.

Clear only if the pasteboard still contains your write:

```swift
pasteboard.clear(ifCurrent: receipt)
```

## Built-in policies

| Policy | Scope | Universal Clipboard | Expiration | Intended use |
| --- | --- | --- | --- | --- |
| `.standard` | System | Allowed | When replaced | Non-sensitive content |
| `.sensitive` | System | Disabled | 60 seconds | Wallet addresses, IBANs, transaction IDs |
| `.oneTimeCode` | System | Disabled | 30 seconds | Short-lived verification codes |
| `.appPasteboard` | App pasteboard | N/A | When replaced | Copy/paste inside the app |
| `.prohibited(reason:)` | None | Disabled | N/A | Seed phrases, private keys, PINs, CVVs |

Every policy is a normal value, so teams can define audited domain-specific presets:

```swift
let walletAddressPolicy = try PasteboardPolicy(
    destination: .system(universalClipboard: .disabled),
    expiration: .after(seconds: 90),
    maximumPayloadSize: 512,
    allowedTypes: .exact([.utf8PlainText])
)
```

## Architecture

- `ProtectedPasteboard` is the policy-enforcing facade.
- `PasteboardPolicy` contains explicit security decisions.
- `PasteboardStore` is the dependency-injection boundary.
- `UIKitPasteboardStore` adapts `UIPasteboard`.
- `PasteboardItem` preserves multiple UTType representations for writes.
- `Receipt` enables identity-bound, best-effort conditional cleanup.

All store access is isolated to `MainActor`, matching UIKit usage and preventing unsynchronized shared state in strict Swift concurrency mode.

## Security boundary

The system pasteboard is a sharing mechanism, not secret storage. Once content is written to the system pasteboard, another app may read it before expiration. `localOnly` prevents Universal Clipboard transfer; it does not make the local pasteboard private.

The app pasteboard is nonpersistent and intended for in-app workflows. It is
not a cryptographic boundary; apps signed by the same team may share named
pasteboards when they know the name.

Use Keychain for persistent credentials and cryptographic key material. Prefer disabling pasteboard access entirely for secrets whose disclosure would compromise an account or wallet.

See [Security](SECURITY.md) and the DocC threat-model article for the complete boundary.

## License

MIT. See [LICENSE](LICENSE).
