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
/// The enum keeps denied writes separate from allowed configurations and makes
/// contradictory states, such as Universal Clipboard on an application-only
/// pasteboard, unrepresentable.
public enum PasteboardPolicy: Sendable, Equatable {
    /// Apply the validated write configuration.
    case allowed(Configuration)

    /// Reject the write before content reaches a pasteboard store.
    case denied(reason: String)

    /// A validated configuration for an allowed write.
    public struct Configuration: Sendable, Equatable {
        /// Where copied content may be consumed.
        public enum Destination: Sendable, Equatable {
            /// The system pasteboard, allowing other local apps to paste.
            case system(universalClipboard: UniversalClipboard)

            /// A unique named pasteboard intended for in-app workflows.
            case applicationOnly
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
            case after(TimeInterval)

            /// Remove the content at an absolute date.
            case at(Date)

            func date(relativeTo now: Date) -> Date? {
                switch self {
                case .whenReplaced:
                    nil
                case let .after(interval):
                    now.addingTimeInterval(interval)
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
                    "Expiration must be a finite number of seconds."
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
            if case let .after(interval) = expiration {
                guard interval.isFinite else {
                    throw ValidationError.nonFiniteExpiration
                }
                guard interval > 0 else {
                    throw ValidationError.nonPositiveExpiration
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
        expiration: .after(60),
        maximumPayloadSize: 64 * 1_024,
        allowedTypes: .exact([.utf8PlainText, .url])
    ))

    /// A short-lived policy suitable for one-time codes.
    static let oneTimeCode = Self.allowed(Configuration(
        validatedDestination: .system(universalClipboard: .disabled),
        expiration: .after(30),
        maximumPayloadSize: 1_024,
        allowedTypes: .exact([.utf8PlainText])
    ))

    /// A unique named pasteboard intended for in-app copy and paste.
    static let applicationOnly = Self.allowed(Configuration(
        validatedDestination: .applicationOnly,
        expiration: .whenReplaced,
        maximumPayloadSize: 1_024 * 1_024
    ))

    /// Explicitly prohibits writing the value to any pasteboard.
    ///
    /// Use this for seed phrases, private keys, PINs, CVVs, and similar secrets.
    static func prohibited(reason: String) -> Self {
        .denied(reason: reason)
    }
}
