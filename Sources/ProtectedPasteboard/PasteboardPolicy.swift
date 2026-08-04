//
//  PasteboardPolicy.swift
//  ProtectedPasteboard
//
//  Created by Tommy on 04.08.2026.
//

import Foundation
import UniformTypeIdentifiers

/// A complete, auditable decision for one pasteboard write.
///
/// The enum keeps prohibited writes separate from allowed configurations and
/// makes contradictory states, such as Universal Clipboard on an app
/// pasteboard, unrepresentable.
public enum PasteboardPolicy: Sendable, Equatable {
    /// Apply the validated write configuration.
    case allowed(Configuration)

    /// Reject the write before content reaches a pasteboard store.
    case prohibited(reason: String)

    /// A validated configuration for an allowed write.
    public struct Configuration: Sendable, Equatable {
        /// Where copied content may be consumed.
        public enum Destination: Sendable, Equatable {
            /// The system pasteboard, allowing other local apps to paste.
            case system(universalClipboard: UniversalClipboard)

            /// A nonpersistent app pasteboard intended for in-app workflows.
            ///
            /// Apps signed by the same team may share named pasteboards when
            /// they know the pasteboard name. This is not a confidentiality
            /// boundary.
            case appPasteboard
        }

        /// Whether Universal Clipboard may transfer system-pasteboard content.
        public enum UniversalClipboard: Sendable, Equatable {
            case allowed
            case disabled
        }

        /// When the operating system should remove the written content.
        public enum Expiration: Sendable, Equatable {
            /// Keep the content until it is replaced or explicitly cleared.
            case whenReplaced

            /// Remove the content after a positive, finite number of seconds.
            case after(seconds: TimeInterval)

            /// Remove the content at an absolute date.
            case at(Date)

            func date(relativeTo now: Date) -> Date? {
                switch self {
                case .whenReplaced:
                    nil
                case let .after(seconds):
                    now.addingTimeInterval(seconds)
                case let .at(date):
                    date
                }
            }
        }

        /// How representation types are matched.
        public enum AllowedTypes: Sendable, Equatable {
            /// Permit every uniform type.
            case any

            /// Permit only identifiers exactly present in the set.
            case exact(Set<UTType>)

            /// Permit types that conform to at least one type in the set.
            case conforming(to: Set<UTType>)

            func contains(_ candidate: UTType) -> Bool {
                switch self {
                case .any:
                    true
                case let .exact(types):
                    types.contains(candidate)
                case let .conforming(types):
                    types.contains { candidate.conforms(to: $0) }
                }
            }
        }

        /// Configuration errors are reported instead of silently normalizing
        /// security-relevant values.
        public enum ValidationError: Error, Sendable, Equatable, LocalizedError {
            case nonPositiveExpiration
            case nonFiniteExpiration
            case nonPositivePayloadLimit
            case emptyTypeSet

            public var errorDescription: String? {
                switch self {
                case .nonPositiveExpiration:
                    "Expiration must be greater than zero seconds."
                case .nonFiniteExpiration:
                    "Expiration must resolve to a finite date."
                case .nonPositivePayloadLimit:
                    "Maximum payload size must be greater than zero bytes."
                case .emptyTypeSet:
                    "An allowed-type set must contain at least one type."
                }
            }
        }

        /// The concrete pasteboard destination.
        public let destination: Destination

        /// The requested operating-system lifetime.
        public let expiration: Expiration

        /// Maximum total payload size in bytes, or `nil` for no package limit.
        public let maximumPayloadSize: Int?

        /// The rule used to accept or reject representation types.
        public let allowedTypes: AllowedTypes

        /// Creates a configuration and rejects invalid security settings.
        public init(
            destination: Destination,
            expiration: Expiration,
            maximumPayloadSize: Int? = nil,
            allowedTypes: AllowedTypes = .any
        ) throws {
            switch expiration {
            case .whenReplaced:
                break
            case let .after(seconds):
                guard seconds.isFinite else {
                    throw ValidationError.nonFiniteExpiration
                }
                guard seconds > 0 else {
                    throw ValidationError.nonPositiveExpiration
                }
            case let .at(date):
                guard date.timeIntervalSinceReferenceDate.isFinite else {
                    throw ValidationError.nonFiniteExpiration
                }
            }

            if let maximumPayloadSize, maximumPayloadSize <= 0 {
                throw ValidationError.nonPositivePayloadLimit
            }

            switch allowedTypes {
            case .any:
                break
            case let .exact(types), let .conforming(types):
                guard types.isEmpty == false else {
                    throw ValidationError.emptyTypeSet
                }
            }

            self.destination = destination
            self.expiration = expiration
            self.maximumPayloadSize = maximumPayloadSize
            self.allowedTypes = allowedTypes
        }

        fileprivate init(
            validatedDestination destination: Destination,
            expiration: Expiration,
            maximumPayloadSize: Int? = nil,
            allowedTypes: AllowedTypes = .any
        ) {
            self.destination = destination
            self.expiration = expiration
            self.maximumPayloadSize = maximumPayloadSize
            self.allowedTypes = allowedTypes
        }
    }

    /// Creates an allowed policy from validated custom settings.
    public init(
        destination: Configuration.Destination,
        expiration: Configuration.Expiration,
        maximumPayloadSize: Int? = nil,
        allowedTypes: Configuration.AllowedTypes = .any
    ) throws {
        self = .allowed(try Configuration(
            destination: destination,
            expiration: expiration,
            maximumPayloadSize: maximumPayloadSize,
            allowedTypes: allowedTypes
        ))
    }
}

public extension PasteboardPolicy {
    /// Conventional cross-app copy behavior with no package-imposed restrictions.
    static let standard = Self.allowed(Configuration(
        validatedDestination: .system(universalClipboard: .allowed),
        expiration: .whenReplaced
    ))

    /// Conservative defaults for financial identifiers and sensitive text.
    static let sensitive = Self.allowed(Configuration(
        validatedDestination: .system(universalClipboard: .disabled),
        expiration: .after(seconds: 60),
        maximumPayloadSize: 64 * 1_024,
        allowedTypes: .exact([.utf8PlainText, .url])
    ))

    /// A short-lived policy suitable for one-time codes.
    static let oneTimeCode = Self.allowed(Configuration(
        validatedDestination: .system(universalClipboard: .disabled),
        expiration: .after(seconds: 30),
        maximumPayloadSize: 1_024,
        allowedTypes: .exact([.utf8PlainText])
    ))

    /// A nonpersistent app pasteboard intended for in-app copy and paste.
    static let appPasteboard = Self.allowed(Configuration(
        validatedDestination: .appPasteboard,
        expiration: .whenReplaced,
        maximumPayloadSize: 1_024 * 1_024
    ))
}
