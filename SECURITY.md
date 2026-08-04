# Security policy

## Reporting a vulnerability

Please do not disclose exploitable vulnerabilities in a public issue. Until a dedicated security contact is published, open a minimal GitHub issue asking the maintainer for a private reporting channel without including sensitive details.

## Threat model

ProtectedPasteboard is intended to reduce accidental exposure caused by unsafe defaults and inconsistent application code. It helps applications:

- disable Universal Clipboard for selected writes;
- request operating-system expiration;
- route internal content to a nonpersistent app pasteboard;
- reject prohibited content before it reaches a store;
- limit payload types and sizes;
- avoid passive payload reads;
- avoid clearing content copied after the application's own write.

## Non-goals

ProtectedPasteboard cannot:

- make the general system pasteboard confidential;
- revoke data another process already read;
- guarantee removal at an exact wall-clock instant;
- replace Keychain or Secure Enclave storage;
- replace Managed Pasteboard policies supplied through device management;
- prevent runtime instrumentation on a compromised or jailbroken device;
- validate domain-specific values such as wallet addresses or IBANs unless the application supplies that validation.

The app pasteboard destination uses a unique named pasteboard. It is intended
for in-app workflows, but it is not a cryptographic isolation boundary. Apps
signed by the same team may share named pasteboards when they know the name.

Conditional cleanup is best-effort. UIKit does not expose an atomic
compare-and-clear operation, so another writer can theoretically race the final
change-count check.

## Recommended classifications

| Data | Recommended policy |
| --- | --- |
| Public text | `.standard` |
| Wallet address, IBAN, transaction ID | `.sensitive` plus domain validation |
| One-time code | `.oneTimeCode` |
| Internal transient UI value | `.appPasteboard` |
| Seed phrase, private key, PIN, CVV | `.prohibited(reason:)` |
