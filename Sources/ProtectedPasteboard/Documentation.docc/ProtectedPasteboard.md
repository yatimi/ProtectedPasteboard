# ``ProtectedPasteboard``

Apply explicit, testable security policies to UIKit pasteboard operations.

## Overview

ProtectedPasteboard is designed for banking, crypto, enterprise, and other
privacy-sensitive applications. It separates policy from UIKit storage so that
teams can review security decisions, inject test stores, and define
domain-specific presets.

```swift
let pasteboard = ProtectedPasteboard.live()

try pasteboard.write(
    walletAddress,
    policy: .sensitive
)
```

The library provides safer defaults, not confidential system storage. Content
written to the general pasteboard may be read by another application before it
expires.

## Topics

### Writing content

- ``ProtectedPasteboard/write(_:policy:)``
- ``PasteboardItem``
- ``PasteboardPolicy``
- ``ProtectedPasteboard/Receipt``

### Reading and inspecting

- ``ProtectedPasteboard/readItemsAfterUserAction(from:)``
- ``ProtectedPasteboard/readStringAfterUserAction(from:)``
- ``ProtectedPasteboard/inspect(location:)``
- ``PasteboardSnapshot``
- ``PasteboardLocation``

### Security model

- <doc:ThreatModel>

### Storage integration

- ``PasteboardStore``
- ``PasteboardWriteOptions``
- ``UIKitPasteboardStore``
