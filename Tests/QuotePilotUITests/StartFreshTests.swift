import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// File → Start Fresh…: one dialog, a backup first, Brand settings kept, clients only if ticked.
@MainActor
@Suite struct StartFreshTests {
    @Test func startingFreshKeepsBrandAndClientsAndRestartsNumbering() throws {
        let model = try UIFixture.sampleModel()
        let brand = model.library.brand
        let clients = model.library.clients
        #expect(!model.library.quotes.isEmpty && !model.library.invoices.isEmpty)
        let before = model.store.backups().count
        model.dialog = .startFresh
        model.startFresh(removingClients: false)
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.section == .dashboard)
        #expect(model.library.quotes.isEmpty)
        #expect(model.library.invoices.isEmpty)
        #expect(model.library.brand == brand)
        #expect(model.library.clients == clients)
        #expect(model.library.activity.map(\.message) == ["Started fresh: removed every quote, invoice and payment, and Activity"])
        #expect(model.library.nextNumber(.quote) == "Q-0001")
        #expect(model.library.nextNumber(.invoice) == "INV-0001")
        // The library as it was is a backup, named for the restore list.
        let backups = model.store.backups()
        #expect(backups.count == before + 1)
        let made = try #require(backups.first { $0.lastPathComponent.contains(LibraryStore.startFreshTag) })
        #expect(AppModel.backupLabel(made) == "15 Oct 2026, before Start Fresh")
        let saved = try Library.makeDecoder().decode(Library.self, from: Data(contentsOf: made))
        #expect(!saved.quotes.isEmpty)
        // And it's saved.
        let reloaded = try Library.makeDecoder().decode(Library.self, from: Data(contentsOf: model.store.libraryURL))
        #expect(reloaded.quotes.isEmpty)
    }

    @Test func theTickBoxRemovesClientsToo() throws {
        let model = try UIFixture.sampleModel()
        model.startFresh(removingClients: true)
        #expect(model.library.clients.isEmpty)
        #expect(model.library.activity.first?.message.contains("client") == true)
    }

    @Test func theDialogDraws() throws {
        let model = try UIFixture.sampleModel()
        model.dialog = .startFresh
        #expect(Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "start-fresh")
            .map(Snapshot.hasContent) == true)
    }
}
