# Contributing

Contributions are welcome when they preserve the library's small, auditable security boundary.

## Development

```sh
swift test
```

Before submitting a change:

1. Add or update Swift Testing coverage.
2. Keep UIKit behind `PasteboardStore`.
3. Document every public declaration.
4. Do not introduce implicit pasteboard reads.
5. Do not log pasteboard payloads.
6. Run `swift test` and `swift package diagnose-api-breaking-changes` when applicable.

## API principles

- Security-relevant defaults must be explicit and testable.
- Core values should conform to `Sendable` where truthful.
- UIKit access remains `MainActor` isolated.
- New dependencies require a clear security and maintenance justification.
- Public API additions need a realistic banking, crypto, or privacy use case.
