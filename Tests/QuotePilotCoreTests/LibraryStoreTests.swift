import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct LibraryStoreTests {
    func tempStore() -> LibraryStore {
        LibraryStore(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotePilotTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func aMissingLibraryStartsFresh() {
        guard case .fresh(let library) = tempStore().load() else {
            Issue.record("expected a fresh library")
            return
        }
        #expect(library.quotes.isEmpty)
    }

    @Test func savesAndLoadsTheSameLibrary() throws {
        let store = tempStore()
        let (library, _) = Fixture.acceptedLibrary()
        try store.save(library)
        guard case .loaded(let loaded) = store.load() else {
            Issue.record("expected the saved library")
            return
        }
        #expect(try Library.makeEncoder().encode(loaded) == Library.makeEncoder().encode(library))
    }

    @Test func refusesToOverwriteAnUnreadableLibrary() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: store.libraryURL)
        guard case .unreadable = store.load() else {
            Issue.record("expected unreadable")
            return
        }
        #expect(throws: LibraryStore.StoreError.wouldOverwriteUnreadableLibrary) { try store.save(Library()) }
        #expect(try Data(contentsOf: store.libraryURL) == garbage)
    }

    @Test func aNewerFormatIsLeftAlone() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data(#"{"format": 99}"#.utf8).write(to: store.libraryURL)
        guard case .unreadable(let reason) = store.load() else {
            Issue.record("expected unreadable")
            return
        }
        #expect(reason.contains("newer version"))
    }

    @Test func backsUpOnceADayAndKeepsThirty() throws {
        let store = tempStore()
        try store.save(Library())
        try FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
        for day in 1...31 {
            let name = String(format: "library-2026-08-%02d.json", day)
            try Data("{}".utf8).write(to: store.backupsFolder.appendingPathComponent(name))
        }
        let made = try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 15))
        #expect(made?.lastPathComponent == "library-2026-10-15.json")
        #expect(try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 15)) == nil)
        let kept = store.backups().map(\.lastPathComponent)
        #expect(kept.count == 30)
        #expect(kept.first == "library-2026-10-15.json")
        #expect(!kept.contains("library-2026-08-01.json"))
        #expect(!kept.contains("library-2026-08-02.json"))
    }

    @Test func restoringKeepsTheFileItReplaces() throws {
        let store = tempStore()
        var older = Library()
        older.brand.businessName = "Sample Studio"
        try store.save(older)
        try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 14))
        var newer = older
        newer.brand.businessName = "Renamed Studio"
        try store.save(newer)

        let restored = try store.restore(from: store.backups()[0])
        #expect(restored.brand.businessName == "Sample Studio")
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        #expect(names.contains { $0.hasPrefix("library-replaced-") })
    }

    @Test func exportsACopyAnywhere() throws {
        let store = tempStore()
        try store.save(Library())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("QuotePilot-copy-\(UUID().uuidString).json")
        try store.exportCopy(to: destination)
        #expect(try Data(contentsOf: destination) == Data(contentsOf: store.libraryURL))
    }
}
