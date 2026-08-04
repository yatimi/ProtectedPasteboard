//
//  UIKitPasteboardStore.swift
//  ProtectedPasteboard
//
//  Created by Tommy on 04.08.2026.
//

#if canImport(UIKit)
import Foundation
import UIKit
import UniformTypeIdentifiers

/// A UIKit-backed pasteboard store.
@MainActor
public final class UIKitPasteboardStore: PasteboardStore {
    fileprivate static let sharedSystemStore = UIKitPasteboardStore(pasteboard: .general)
    fileprivate static let sharedApplicationStore = UIKitPasteboardStore(
        pasteboard: .withUniqueName()
    )

    private let pasteboard: UIPasteboard
    private var cachedSnapshot: PasteboardSnapshot?

    /// Wraps an existing UIKit pasteboard.
    public init(pasteboard: UIPasteboard) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func snapshot() -> PasteboardSnapshot {
        let initialChangeCount = changeCount
        if let cachedSnapshot, cachedSnapshot.changeCount == initialChangeCount {
            return cachedSnapshot
        }

        var snapshot = makeSnapshot(changeCount: initialChangeCount)
        let finalChangeCount = changeCount
        if finalChangeCount != initialChangeCount {
            snapshot = makeSnapshot(changeCount: finalChangeCount)
        }

        cachedSnapshot = snapshot
        return snapshot
    }

    @discardableResult
    public func replaceItems(
        _ items: [PasteboardItem],
        options: PasteboardWriteOptions
    ) throws -> Int {
        let payload = items.map { item in
            Dictionary(uniqueKeysWithValues: item.representations.map { representation in
                (representation.type.identifier, representation.data)
            })
        }

        var uiOptions: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: options.localOnly,
        ]
        if let expirationDate = options.expirationDate {
            uiOptions[.expirationDate] = expirationDate
        }

        pasteboard.setItems(payload, options: uiOptions)
        cachedSnapshot = nil
        return pasteboard.changeCount
    }

    public func readItems() throws -> [PasteboardItem] {
        let itemCount = pasteboard.numberOfItems
        guard itemCount > 0 else {
            return []
        }

        return try (0..<itemCount).compactMap { itemIndex in
            let representations = representations(at: itemIndex)
            guard representations.isEmpty == false else {
                return nil
            }
            return try PasteboardItem(representations: representations)
        }
    }

    public func readFirstRepresentation(
        matching requestedType: UTType
    ) throws -> PasteboardItem.Representation? {
        let itemCount = pasteboard.numberOfItems
        guard itemCount > 0 else {
            return nil
        }

        for itemIndex in 0..<itemCount {
            for identifier in typeIdentifiers(at: itemIndex) {
                guard
                    let type = UTType(identifier),
                    type == requestedType,
                    let data = data(forType: identifier, at: itemIndex)
                else {
                    continue
                }

                return PasteboardItem.Representation(type: type, data: data)
            }
        }
        return nil
    }

    @discardableResult
    public func removeAllItems() -> Int {
        pasteboard.items = []
        cachedSnapshot = nil
        return pasteboard.changeCount
    }

    private func makeSnapshot(changeCount: Int) -> PasteboardSnapshot {
        let itemCount = pasteboard.numberOfItems
        let items = (0..<itemCount).map { itemIndex in
            PasteboardSnapshot.Item(
                typeIdentifiers: typeIdentifiers(at: itemIndex)
            )
        }
        return PasteboardSnapshot(changeCount: changeCount, items: items)
    }

    private func representations(at itemIndex: Int) -> [PasteboardItem.Representation] {
        typeIdentifiers(at: itemIndex).compactMap { identifier in
            guard
                let type = UTType(identifier),
                let data = data(forType: identifier, at: itemIndex)
            else {
                return nil
            }
            return PasteboardItem.Representation(type: type, data: data)
        }
    }

    private func typeIdentifiers(at itemIndex: Int) -> [String] {
        pasteboard.types(forItemSet: IndexSet(integer: itemIndex))?.first ?? []
    }

    private func data(forType identifier: String, at itemIndex: Int) -> Data? {
        pasteboard.data(
            forPasteboardType: identifier,
            inItemSet: IndexSet(integer: itemIndex)
        )?.first
    }
}

public extension ProtectedPasteboard {
    /// Creates a production facade backed by app-wide system and private stores.
    ///
    /// Prefer creating this once at the application's composition root and
    /// injecting it into features that need pasteboard access.
    static func live() -> ProtectedPasteboard {
        ProtectedPasteboard(
            systemStore: UIKitPasteboardStore.sharedSystemStore,
            applicationStore: UIKitPasteboardStore.sharedApplicationStore
        )
    }
}
#endif
