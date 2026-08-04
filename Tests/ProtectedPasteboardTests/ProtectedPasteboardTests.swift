//
//  ProtectedPasteboardTests.swift
//  ProtectedPasteboardTests
//
//  Created by Tommy on 04.08.2026.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ProtectedPasteboard

@MainActor
struct ProtectedPasteboardTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Sensitive writes disable Handoff and expire")
    func sensitiveWriteResolvesSecureOptions() throws {
        let system = InMemoryPasteboardStore()
        let application = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system, application: application)

        let receipt = try pasteboard.write("DE89 3704 0044 0532 0130 00", policy: .sensitive)

        #expect(system.items == [.text("DE89 3704 0044 0532 0130 00")])
        #expect(system.lastOptions?.localOnly == true)
        #expect(system.lastOptions?.expirationDate == now.addingTimeInterval(60))
        #expect(receipt.location == .system)
        #expect(receipt.expirationDate == now.addingTimeInterval(60))
        #expect(application.items.isEmpty)
    }

    @Test("Application-only writes never touch the system store")
    func applicationOnlyRoutesToPrivateStore() throws {
        let system = InMemoryPasteboardStore()
        let application = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system, application: application)

        let receipt = try pasteboard.write("internal value", policy: .applicationOnly)

        #expect(system.items.isEmpty)
        #expect(application.items == [.text("internal value")])
        #expect(application.lastOptions?.localOnly == true)
        #expect(receipt.location == .applicationOnly)
    }

    @Test("Prohibited values never reach a store")
    func prohibitedPolicyRejectsWrite() {
        let system = InMemoryPasteboardStore()
        let application = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system, application: application)
        let policy = PasteboardPolicy.prohibited(reason: "Seed phrases must not enter a pasteboard.")

        #expect(throws: ProtectedPasteboard.Error.writeProhibited(
            reason: "Seed phrases must not enter a pasteboard."
        )) {
            try pasteboard.write("abandon abandon abandon", policy: policy)
        }
        #expect(system.writeCount == 0)
        #expect(application.writeCount == 0)
    }

    @Test("Policy rejects oversized payloads")
    func payloadLimitIsEnforced() throws {
        let system = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system)
        let policy = try PasteboardPolicy(
            destination: .system(universalClipboard: .disabled),
            expiration: .after(10),
            maximumPayloadSize: 3
        )

        #expect(throws: ProtectedPasteboard.Error.payloadTooLarge(actual: 4, maximum: 3)) {
            try pasteboard.write("1234", policy: policy)
        }
        #expect(system.writeCount == 0)
    }

    @Test("Policy rejects representations outside its allowlist")
    func typeAllowlistIsEnforced() {
        let system = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system)
        let item = PasteboardItem.data(Data([0xCA, 0xFE]), type: .png)

        #expect(throws: ProtectedPasteboard.Error.disallowedType(UTType.png.identifier)) {
            try pasteboard.write(item, policy: .sensitive)
        }
        #expect(system.writeCount == 0)
    }

    @Test("Text reads decode UTF-8 without loading all items")
    func userInitiatedReadReturnsText() throws {
        let system = InMemoryPasteboardStore(items: [.text("hello")])
        let pasteboard = makePasteboard(system: system)

        let value = try pasteboard.readStringAfterUserAction()

        #expect(value == "hello")
        #expect(system.selectiveReadCount == 1)
        #expect(system.fullReadCount == 0)
    }

    @Test("Text reads select exact UTF-8 representation deterministically")
    func textReadDoesNotDecodeHTMLAsPlainText() throws {
        let item = try PasteboardItem(representations: [
            .init(type: .html, data: Data("<b>wrong</b>".utf8)),
            .init(type: .utf8PlainText, data: Data("correct".utf8)),
        ])
        let system = InMemoryPasteboardStore(items: [item])
        let pasteboard = makePasteboard(system: system)

        let value = try pasteboard.readStringAfterUserAction()

        #expect(value == "correct")
    }

    @Test("Receipt clearing preserves content copied later")
    func staleReceiptDoesNotClearNewContent() throws {
        let system = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system)
        let receipt = try pasteboard.write("first", policy: .sensitive)
        system.simulateExternalWrite([.text("new user content")])

        let didClear = pasteboard.clear(ifCurrent: receipt)

        #expect(didClear == false)
        #expect(system.items == [.text("new user content")])
    }

    @Test("Receipt clears the exact write it represents")
    func currentReceiptClearsContent() throws {
        let system = InMemoryPasteboardStore()
        let pasteboard = makePasteboard(system: system)
        let receipt = try pasteboard.write("temporary", policy: .sensitive)

        let didClear = pasteboard.clear(ifCurrent: receipt)

        #expect(didClear)
        #expect(system.items.isEmpty)
    }

    @Test("Snapshot inspection does not decode payloads")
    func inspectionUsesMetadataOnly() throws {
        let url = try #require(URL(string: "https://example.com"))
        let system = InMemoryPasteboardStore(items: [.url(url)])
        let pasteboard = makePasteboard(system: system)

        let snapshot = pasteboard.inspect()

        #expect(snapshot.items.count == 1)
        #expect(snapshot.items.first?.types == [.url, .utf8PlainText])
        #expect(system.fullReadCount == 0)
        #expect(system.selectiveReadCount == 0)
    }

    @Test("Receipt cannot clear through another facade")
    func receiptIsBoundToItsFacade() throws {
        let system = InMemoryPasteboardStore()
        let application = InMemoryPasteboardStore()
        let writer = makePasteboard(system: system, application: application)
        let otherFacade = makePasteboard(system: system, application: application)
        let receipt = try writer.write("temporary", policy: .sensitive)

        let didClear = otherFacade.clear(ifCurrent: receipt)

        #expect(didClear == false)
        #expect(system.items == [.text("temporary")])
    }

    @Test("Invalid policy settings are rejected")
    func invalidConfigurationIsRejected() {
        #expect(throws: PasteboardPolicy.Configuration.ValidationError.nonPositiveExpiration) {
            try PasteboardPolicy(
                destination: .system(universalClipboard: .disabled),
                expiration: .after(0)
            )
        }

        #expect(throws: PasteboardPolicy.Configuration.ValidationError.nonPositivePayloadLimit) {
            try PasteboardPolicy(
                destination: .applicationOnly,
                expiration: .whenReplaced,
                maximumPayloadSize: -1
            )
        }
    }

    private func makePasteboard(
        system: InMemoryPasteboardStore = InMemoryPasteboardStore(),
        application: InMemoryPasteboardStore = InMemoryPasteboardStore()
    ) -> ProtectedPasteboard {
        ProtectedPasteboard(
            systemStore: system,
            applicationStore: application,
            now: { now }
        )
    }
}

@MainActor
private final class InMemoryPasteboardStore: PasteboardStore {
    private(set) var changeCount = 0
    private(set) var items: [PasteboardItem]
    private(set) var lastOptions: PasteboardWriteOptions?
    private(set) var writeCount = 0
    private(set) var fullReadCount = 0
    private(set) var selectiveReadCount = 0

    init(items: [PasteboardItem] = []) {
        self.items = items
    }

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(
            changeCount: changeCount,
            items: items.map { item in
                PasteboardSnapshot.Item(types: item.representations.map(\.type))
            }
        )
    }

    func replaceItems(
        _ items: [PasteboardItem],
        options: PasteboardWriteOptions
    ) throws -> Int {
        self.items = items
        lastOptions = options
        writeCount += 1
        changeCount += 1
        return changeCount
    }

    func readItems() throws -> [PasteboardItem] {
        fullReadCount += 1
        return items
    }

    func readFirstRepresentation(
        matching type: UTType
    ) throws -> PasteboardItem.Representation? {
        selectiveReadCount += 1
        return items
            .lazy
            .flatMap(\.representations)
            .first { representation in
                representation.type == type
            }
    }

    func removeAllItems() -> Int {
        items = []
        changeCount += 1
        return changeCount
    }

    func simulateExternalWrite(_ items: [PasteboardItem]) {
        self.items = items
        changeCount += 1
    }
}
