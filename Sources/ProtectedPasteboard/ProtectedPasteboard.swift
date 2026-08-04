//
//  ProtectedPasteboard.swift
//  ProtectedPasteboard
//
//  Created by Tommy on 04.08.2026.
//

import Foundation
import UniformTypeIdentifiers

/// A policy-enforcing facade over system and app pasteboards.
@MainActor
public final class ProtectedPasteboard {
    /// An opaque handle for conditionally clearing one write.
    ///
    /// Receipts are bound to the `ProtectedPasteboard` instance that created
    /// them. Cleanup remains best-effort because the operating system does not
    /// provide an atomic compare-and-clear operation.
    public struct Receipt: Sendable, Equatable {
        /// Where the content was written.
        public let location: PasteboardLocation

        /// The date at which the write occurred.
        public let writtenAt: Date

        /// The requested operating-system expiration date, if any.
        public let expirationDate: Date?

        fileprivate let ownerID: UUID
        fileprivate let changeCount: Int

        /// Returns whether the requested expiration date has passed.
        public func isExpired(at date: Date = Date()) -> Bool {
            guard let expirationDate else {
                return false
            }
            return date >= expirationDate
        }
    }

    /// Errors produced while enforcing a policy or decoding content.
    public enum Error: Swift.Error, Sendable, Equatable, LocalizedError {
        case prohibited(reason: String)
        case emptyWrite
        case invalidMaximumByteCount
        case payloadTooLarge(actual: Int, maximum: Int)
        case disallowedType(String)
        case invalidUTF8

        public var errorDescription: String? {
            switch self {
            case let .prohibited(reason):
                "Pasteboard writes are prohibited: \(reason)"
            case .emptyWrite:
                "At least one pasteboard item is required."
            case .invalidMaximumByteCount:
                "Maximum byte count must be greater than zero."
            case let .payloadTooLarge(actual, maximum):
                "The pasteboard payload is \(actual) bytes; the policy allows \(maximum) bytes."
            case let .disallowedType(identifier):
                "The policy does not allow the representation type \(identifier)."
            case .invalidUTF8:
                "The selected UTF-8 representation contains invalid data."
            }
        }
    }

    private let ownerID = UUID()
    private let systemStore: any PasteboardStore
    private let appPasteboardStore: any PasteboardStore
    private let now: () -> Date

    /// Creates a facade with explicit, replaceable storage dependencies.
    public init(
        systemStore: any PasteboardStore,
        appPasteboardStore: any PasteboardStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.systemStore = systemStore
        self.appPasteboardStore = appPasteboardStore
        self.now = now
    }

    /// Writes one item after enforcing every rule in `policy`.
    @discardableResult
    public func write(
        _ item: PasteboardItem,
        policy: PasteboardPolicy
    ) throws -> Receipt {
        try write([item], policy: policy)
    }

    /// Writes multiple items after enforcing every rule in `policy`.
    @discardableResult
    public func write(
        _ items: [PasteboardItem],
        policy: PasteboardPolicy
    ) throws -> Receipt {
        let configuration: PasteboardPolicy.Configuration
        switch policy {
        case let .allowed(value):
            configuration = value
        case let .prohibited(reason):
            throw Error.prohibited(reason: reason)
        }

        try validate(items, configuration: configuration)

        let writeDate = now()
        let expirationDate = configuration.expiration.date(relativeTo: writeDate)
        let options = PasteboardWriteOptions(
            localOnly: configuration.destination.localOnly,
            expirationDate: expirationDate
        )
        let changeCount = try store(for: configuration.destination).replaceItems(
            items,
            options: options
        )

        return Receipt(
            location: configuration.destination.location,
            writtenAt: writeDate,
            expirationDate: expirationDate,
            ownerID: ownerID,
            changeCount: changeCount
        )
    }

    /// Convenience for policy-protected UTF-8 text writes.
    @discardableResult
    public func write(
        _ text: String,
        policy: PasteboardPolicy
    ) throws -> Receipt {
        try write(.text(text), policy: policy)
    }

    /// Inspects types and change count without decoding item payloads.
    public func inspect(
        location: PasteboardLocation = .system
    ) -> PasteboardSnapshot {
        store(at: location).snapshot()
    }

    /// Reads the first representation with exactly the requested type.
    ///
    /// The method name is an API-level reminder, not proof of user intent. Call
    /// it only from a system paste action, `UIPasteControl`, or an equivalent
    /// interaction initiated by the user. UIKit may materialize provider-backed
    /// data before the size limit can be enforced.
    public func readDataAfterUserAction(
        ofExactType type: UTType,
        maximumByteCount: Int,
        from location: PasteboardLocation = .system
    ) throws -> Data? {
        guard maximumByteCount > 0 else {
            throw Error.invalidMaximumByteCount
        }

        guard let data = try store(at: location)
            .readFirstRepresentation(ofExactType: type)?
            .data
        else {
            return nil
        }

        guard data.count <= maximumByteCount else {
            throw Error.payloadTooLarge(
                actual: data.count,
                maximum: maximumByteCount
            )
        }
        return data
    }

    /// Reads the first exact UTF-8 plain-text representation after a user action.
    public func readStringAfterUserAction(
        from location: PasteboardLocation = .system,
        maximumByteCount: Int = 64 * 1_024
    ) throws -> String? {
        guard let data = try readDataAfterUserAction(
            ofExactType: .utf8PlainText,
            maximumByteCount: maximumByteCount,
            from: location
        )
        else {
            return nil
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw Error.invalidUTF8
        }
        return value
    }

    /// Returns whether metadata advertises a representation conforming to `type`.
    ///
    /// This method does not intentionally decode pasteboard payloads. An
    /// advertised representation may still fail to load when the user pastes.
    public func advertisesContent(
        conformingTo type: UTType,
        at location: PasteboardLocation = .system
    ) -> Bool {
        inspect(location: location).items.lazy
            .flatMap(\.typeIdentifiers)
            .contains { identifier in
                UTType(identifier)?.conforms(to: type) == true
            }
    }

    /// Clears a write only when it belongs to this facade and its change count
    /// is still current.
    ///
    /// This is best-effort: `UIPasteboard` has no atomic compare-and-clear API.
    @discardableResult
    public func clear(ifCurrent receipt: Receipt) -> Bool {
        guard receipt.ownerID == ownerID else {
            return false
        }

        let target = store(at: receipt.location)
        guard target.changeCount == receipt.changeCount else {
            return false
        }
        target.removeAllItems()
        return true
    }

    /// Explicitly clears the selected destination regardless of current content.
    public func clear(location: PasteboardLocation) {
        store(at: location).removeAllItems()
    }

    private func validate(
        _ items: [PasteboardItem],
        configuration: PasteboardPolicy.Configuration
    ) throws {
        guard items.isEmpty == false else {
            throw Error.emptyWrite
        }

        for representation in items.lazy.flatMap(\.representations) {
            guard configuration.allowedTypes.contains(representation.type) else {
                throw Error.disallowedType(representation.type.identifier)
            }
        }

        guard let maximum = configuration.maximumPayloadSize else {
            return
        }

        var total = 0
        for representation in items.lazy.flatMap(\.representations) {
            let byteCount = representation.data.count
            guard byteCount <= maximum - total else {
                let actual = total.addingReportingOverflow(byteCount)
                throw Error.payloadTooLarge(
                    actual: actual.overflow ? .max : actual.partialValue,
                    maximum: maximum
                )
            }
            total += byteCount
        }
    }

    private func store(
        for destination: PasteboardPolicy.Configuration.Destination
    ) -> any PasteboardStore {
        store(at: destination.location)
    }

    private func store(at location: PasteboardLocation) -> any PasteboardStore {
        switch location {
        case .system:
            systemStore
        case .appPasteboard:
            appPasteboardStore
        }
    }
}

private extension PasteboardPolicy.Configuration.Destination {
    var location: PasteboardLocation {
        switch self {
        case .system:
            .system
        case .appPasteboard:
            .appPasteboard
        }
    }

    var localOnly: Bool {
        switch self {
        case let .system(universalClipboard):
            universalClipboard == .disabled
        case .appPasteboard:
            true
        }
    }
}
