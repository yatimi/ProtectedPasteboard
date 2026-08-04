# Threat Model

Understand what ProtectedPasteboard can and cannot protect.

## Security goals

ProtectedPasteboard centralizes pasteboard decisions that are otherwise easy to
scatter across an application. It can reject prohibited writes, select an
app-pasteboard destination, disable Universal Clipboard, request expiration,
limit payload size and types, and avoid overwriting content copied later during
best-effort cleanup.

## System pasteboard boundary

The general pasteboard is a sharing mechanism. Content written there may be
read by another application before its requested expiration. Disabling
Universal Clipboard prevents transfer to nearby devices; it does not make the
local system pasteboard confidential.

Use Keychain for credentials and cryptographic key material. Seed phrases,
private keys, PINs, and CVVs should normally use a prohibited policy.

## App pasteboard destination

The app pasteboard destination uses one unique named pasteboard shared by the
production facade. It is intended for in-app workflows and is not a
cryptographic boundary. Other apps signed by the same team may share named
pasteboards if they know the name.

## Reading

Methods whose names end in `AfterUserAction` are reminders for the caller. The
library cannot prove that an interaction occurred. Invoke them from a standard
paste action, `UIPasteControl` on iOS 16 or later, or an equivalent explicit
user interaction.

## Cleanup races

A receipt is bound to the facade that created it and records the pasteboard
change count after writing. Conditional cleanup checks both before clearing.
UIKit does not offer an atomic compare-and-clear operation, so cleanup remains
best-effort if another process writes during that final operation.
