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
    fileprivate static let sharedAppPasteboardStore = UIKitPasteboardStore(
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
        let observedChangeCount = changeCount
        if let cachedSnapshot, cachedSnapshot.changeCount == observedChangeCount {
            return cachedSnapshot
        }

        for _ in 0..<2 {
            let initialChangeCount = changeCount
            let snapshot = makeSnapshot(changeCount: initialChangeCount)
            guard changeCount == initialChangeCount else {
                continue
            }

            cachedSnapshot = snapshot
            return snapshot
        }

        let fallbackChangeCount = changeCount
        return makeSnapshot(changeCount: fallbackChangeCount)
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

    public func readFirstRepresentation(
        ofExactType requestedType: UTType
    ) throws -> PasteboardItem.Representation? {
        let itemCount = pasteboard.numberOfItems
        guard itemCount > 0 else {
            return nil
        }

        let itemSet = IndexSet(integersIn: 0..<itemCount)
        guard let data = pasteboard.data(
            forPasteboardType: requestedType.identifier,
            inItemSet: itemSet
        )?.first else {
            return nil
        }

        return PasteboardItem.Representation(type: requestedType, data: data)
    }

    @discardableResult
    public func removeAllItems() -> Int {
        pasteboard.items = []
        cachedSnapshot = nil
        return pasteboard.changeCount
    }

    private func makeSnapshot(changeCount: Int) -> PasteboardSnapshot {
        let itemCount = pasteboard.numberOfItems
        guard itemCount > 0 else {
            return PasteboardSnapshot(changeCount: changeCount, items: [])
        }

        let itemSet = IndexSet(integersIn: 0..<itemCount)
        let items = pasteboard.types(forItemSet: itemSet)?.map { identifiers in
            PasteboardSnapshot.Item(typeIdentifiers: identifiers)
        } ?? []
        return PasteboardSnapshot(changeCount: changeCount, items: items)
    }
}

public extension ProtectedPasteboard {
    /// The app-wide production facade backed by system and app pasteboards.
    static let shared = ProtectedPasteboard(
        systemStore: UIKitPasteboardStore.sharedSystemStore,
        appPasteboardStore: UIKitPasteboardStore.sharedAppPasteboardStore
    )
}
#endif
