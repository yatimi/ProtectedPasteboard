//
//  PasteboardStore.swift
//  ProtectedPasteboard
//
//  Created by Tommy on 04.08.2026.
//

import Foundation
import UniformTypeIdentifiers

/// A concrete pasteboard selected for reading, inspection, or clearing.
public enum PasteboardLocation: Sendable, Equatable {
    /// The systemwide general pasteboard.
    case system

    /// The package's nonpersistent app pasteboard.
    case appPasteboard
}

/// Options already resolved for a concrete pasteboard store.
public struct PasteboardWriteOptions: Sendable, Equatable {
    /// Whether the item must stay on the current device.
    public let localOnly: Bool

    /// The requested operating-system expiration date.
    public let expirationDate: Date?

    /// Creates resolved options for a concrete store write.
    public init(localOnly: Bool, expirationDate: Date?) {
        self.localOnly = localOnly
        self.expirationDate = expirationDate
    }
}

/// Metadata that can be inspected without intentionally decoding item payloads.
public struct PasteboardSnapshot: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        /// Raw type identifiers advertised by one pasteboard item.
        ///
        /// Raw identifiers are preserved even when the operating system cannot
        /// resolve them to modern `UTType` values.
        public let typeIdentifiers: [String]

        /// Resolved modern uniform types, in pasteboard order.
        public var types: [UTType] {
            typeIdentifiers.compactMap(UTType.init)
        }

        /// Creates item metadata from advertised uniform types.
        public init(types: [UTType]) {
            typeIdentifiers = types.map(\.identifier)
        }

        /// Creates item metadata while preserving raw identifiers.
        public init(typeIdentifiers: [String]) {
            self.typeIdentifiers = typeIdentifiers
        }
    }

    /// Change count observed for this metadata snapshot.
    public let changeCount: Int

    /// Metadata for each item in pasteboard order.
    public let items: [Item]

    /// Creates a metadata snapshot.
    public init(changeCount: Int, items: [Item]) {
        self.changeCount = changeCount
        self.items = items
    }
}

/// Storage boundary used by `ProtectedPasteboard`.
///
/// The protocol keeps UIKit out of policy tests and lets applications provide
/// audited or platform-specific stores without changing the high-level API.
@MainActor
public protocol PasteboardStore: AnyObject {
    /// A monotonically changing value supplied by the underlying pasteboard.
    var changeCount: Int { get }

    /// Returns item types without intentionally decoding the payloads.
    func snapshot() -> PasteboardSnapshot

    /// Replaces the store contents and returns the resulting change count.
    @discardableResult
    func replaceItems(
        _ items: [PasteboardItem],
        options: PasteboardWriteOptions
    ) throws -> Int

    /// Reads only the first representation with exactly the requested type.
    ///
    /// Stores should avoid decoding unrelated payloads while serving this request.
    func readFirstRepresentation(
        ofExactType type: UTType
    ) throws -> PasteboardItem.Representation?

    /// Removes every item and returns the resulting change count.
    @discardableResult
    func removeAllItems() -> Int
}
