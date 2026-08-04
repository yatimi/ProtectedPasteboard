//
//  PasteboardItem.swift
//  ProtectedPasteboard
//
//  Created by Tommy on 04.08.2026.
//

import Foundation
import UniformTypeIdentifiers

/// A value placed on a pasteboard.
///
/// A single item may contain multiple supported representations of the same value. For
/// example, formatted text may include plain-text, HTML, and RTF representations.
public struct PasteboardItem: Sendable, Equatable {
    /// A single encoded representation of a pasteboard item.
    public struct Representation: Sendable, Equatable, Hashable {
        /// The uniform type identifier describing `data`.
        public let type: UTType

        /// The representation's encoded bytes.
        public let data: Data

        /// Creates an encoded representation.
        public init(type: UTType, data: Data) {
            self.type = type
            self.data = data
        }
    }

    /// Errors produced while constructing an item.
    public enum ValidationError: Error, Sendable, Equatable {
        /// Every pasteboard item must contain at least one representation.
        case emptyRepresentations

        /// An item cannot contain the same uniform type more than once.
        case duplicateType(String)
    }

    /// Every encoded representation carried by this item.
    public let representations: [Representation]

    /// Creates an item while preserving every supplied representation.
    public init(representations: [Representation]) throws {
        guard representations.isEmpty == false else {
            throw ValidationError.emptyRepresentations
        }

        var identifiers = Set<String>()
        for representation in representations {
            let inserted = identifiers.insert(representation.type.identifier).inserted
            guard inserted else {
                throw ValidationError.duplicateType(representation.type.identifier)
            }
        }

        self.representations = representations
    }

    /// Creates a plain UTF-8 text item.
    public static func text(_ value: String) -> Self {
        Self(
            validatedRepresentations: [
                Representation(type: .utf8PlainText, data: Data(value.utf8)),
            ]
        )
    }

    /// Creates a URL item with URL and plain-text representations.
    public static func url(_ value: URL) -> Self {
        let data = Data(value.absoluteString.utf8)
        return Self(
            validatedRepresentations: [
                Representation(type: .url, data: data),
                Representation(type: .utf8PlainText, data: data),
            ]
        )
    }

    /// Creates an item containing one arbitrary uniform type.
    public static func data(_ data: Data, type: UTType) -> Self {
        Self(validatedRepresentations: [Representation(type: type, data: data)])
    }

    /// Total encoded size across all representations, saturated at `Int.max`.
    public var byteCount: Int {
        representations.reduce(into: 0) { total, representation in
            let addition = total.addingReportingOverflow(representation.data.count)
            total = addition.overflow ? .max : addition.partialValue
        }
    }

    private init(validatedRepresentations: [Representation]) {
        representations = validatedRepresentations
    }
}
