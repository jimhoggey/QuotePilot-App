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
        // Saving must not replace it either (Review Focus item 4).
        let before = try Data(contentsOf: store.libraryURL)
        #expect(throws: LibraryStore.StoreError.wouldOverwriteUnreadableLibrary) { try store.save(Library()) }
        #expect(try Data(contentsOf: store.libraryURL) == before)
    }

    /// A library holding a day that doesn't exist: Day's public init refuses to build one, so this uses
    /// the unchecked init the decoder shares with `Day(iso:)`.
    func libraryWithAnImpossibleDay() -> Library {
        var (library, _) = Fixture.acceptedLibrary()
        library.quotes[0].issued = Day(uncheckedYear: 2026, month: 2, day: 31)
        return library
    }

    @Test func neverWritesALibraryTheNextLaunchCantRead() throws {
        let store = tempStore()
        var good = Library()
        good.brand.businessName = "Sample Studio"
        try store.save(good)
        let before = try Data(contentsOf: store.libraryURL)

        let bad = libraryWithAnImpossibleDay()
        #expect(String(decoding: try Library.makeEncoder().encode(bad), as: UTF8.self).contains("2026-02-31"))
        #expect(throws: LibraryStore.StoreError.wouldWriteUnreadableLibrary) { try store.save(bad) }
        #expect(try Data(contentsOf: store.libraryURL) == before)
        guard case .loaded(let loaded) = store.load() else {
            Issue.record("the saved library should still read")
            return
        }
        #expect(loaded.brand.businessName == "Sample Studio")
    }

    @Test func aFirstSaveOfAnUnreadableLibraryWritesNothing() throws {
        let store = tempStore()
        #expect(throws: LibraryStore.StoreError.wouldWriteUnreadableLibrary) { try store.save(libraryWithAnImpossibleDay()) }
        #expect(!FileManager.default.fileExists(atPath: store.libraryURL.path))
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
        let replacedName = try #require(names.first { $0.hasPrefix("library-replaced-") })
        let replaced = try Library.makeDecoder().decode(Library.self,
                                                        from: Data(contentsOf: store.folder.appendingPathComponent(replacedName)))
        #expect(replaced.brand.businessName == "Renamed Studio")
        guard case .loaded(let current) = store.load() else {
            Issue.record("expected the restored library")
            return
        }
        #expect(current.brand.businessName == "Sample Studio")
    }

    @Test func noBackupOfAnUnreadableLibrary() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.libraryURL)
        #expect(try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 15)) == nil)
        #expect(store.backups().isEmpty)
    }

    @Test func restoreRefusesABackupFromANewerVersion() throws {
        let store = tempStore()
        var current = Library()
        current.brand.businessName = "Sample Studio"
        try store.save(current)
        let before = try Data(contentsOf: store.libraryURL)
        var newer = Library()
        newer.format = 99
        newer.brand.businessName = "Future Studio"
        try FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
        let backup = store.backupsFolder.appendingPathComponent("library-2026-10-14.json")
        try Library.makeEncoder().encode(newer).write(to: backup)
        #expect(throws: LibraryStore.StoreError.backupFromNewerVersion(99)) { try store.restore(from: backup) }
        #expect(try Data(contentsOf: store.libraryURL) == before)
    }

    @Test func restoringAGarbageBackupChangesNothing() throws {
        let store = tempStore()
        try store.save(Library())
        let before = try Data(contentsOf: store.libraryURL)
        try FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
        let backup = store.backupsFolder.appendingPathComponent("library-2026-10-14.json")
        try Data("{ not json".utf8).write(to: backup)
        #expect(throws: DecodingError.self) { try store.restore(from: backup) }
        #expect(try Data(contentsOf: store.libraryURL) == before)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        #expect(!names.contains { $0.hasPrefix("library-replaced-") })
    }

    @Test func anUnreadableLibraryCanBeRestored() throws {
        let store = tempStore()
        var good = Library()
        good.brand.businessName = "Sample Studio"
        try store.save(good)
        try store.backUpIfDue(today: Day(year: 2026, month: 10, day: 14))
        try Data("{ not json".utf8).write(to: store.libraryURL)
        try store.restore(from: store.backups()[0])
        guard case .loaded(let restored) = store.load() else {
            Issue.record("expected the restored library")
            return
        }
        #expect(restored.brand.businessName == "Sample Studio")
    }

    /// The fixture library with a $20,000,000 rate on Q-0001's line 02: a typo or a hand edit. Adding
    /// amounts like that up can overflow, which would stop the app every time it opened.
    func libraryWithAnAbsurdRate() -> Library {
        var (library, _) = Fixture.libraryWithQuote()
        library.quotes[0].lines[1].rate = Money(dollars: 20_000_000)
        return library
    }

    @Test func aLibraryWithAnAbsurdAmountLoadsAsUnreadable() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Library.makeEncoder().encode(libraryWithAnAbsurdRate()).write(to: store.libraryURL)
        guard case .unreadable(let reason) = store.load() else {
            Issue.record("expected unreadable")
            return
        }
        #expect(reason.contains("Q-0001 line 02 has a rate of $20,000,000.00, over the $10,000,000.00 limit."))
        // Nothing saves over it, and it never becomes a backup.
        let before = try Data(contentsOf: store.libraryURL)
        #expect(throws: LibraryStore.StoreError.wouldOverwriteUnreadableLibrary) { try store.save(Library()) }
        #expect(try store.backUpIfDue(today: Fixture.today) == nil)
        #expect(try Data(contentsOf: store.libraryURL) == before)
    }

    @Test func theReasonListsThreeProblemsAndCountsTheRest() throws {
        let store = tempStore()
        var library = libraryWithAnAbsurdRate()
        library.quotes[0].lines[0].quantity = -1
        library.quotes[0].lines[2].quantity = 200_000
        library.brand.paymentDueDays = 9_999
        library.brand.quoteValidDays = 9_999
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Library.makeEncoder().encode(library).write(to: store.libraryURL)
        guard case .unreadable(let reason) = store.load() else {
            Issue.record("expected unreadable")
            return
        }
        #expect(reason.hasPrefix("It holds numbers Quote Pilot can't work with."))
        #expect(reason.hasSuffix("And 2 more."))
    }

    @Test func neverWritesALibraryWithAbsurdAmounts() throws {
        let store = tempStore()
        #expect(throws: LibraryStore.StoreError.wouldWriteUnreadableLibrary) { try store.save(libraryWithAnAbsurdRate()) }
        #expect(!FileManager.default.fileExists(atPath: store.libraryURL.path))
    }

    @Test func restoreRefusesABackupWithAbsurdAmounts() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let damaged = Data("{ not json".utf8)
        try damaged.write(to: store.libraryURL)
        try FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
        let backup = store.backupsFolder.appendingPathComponent("library-2026-10-14.json")
        try Library.makeEncoder().encode(libraryWithAnAbsurdRate()).write(to: backup)

        let error = #expect(throws: LibraryStore.StoreError.self) { try store.restore(from: backup) }
        #expect(error?.localizedDescription.hasPrefix("That backup holds numbers Quote Pilot can't work with") == true)
        #expect(error?.localizedDescription.contains("$20,000,000.00") == true)
        #expect(try Data(contentsOf: store.libraryURL) == damaged)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        #expect(!names.contains { $0.hasPrefix("library-replaced-") })
    }

    @Test func exportsACopyAnywhere() throws {
        let store = tempStore()
        try store.save(Library())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("QuotePilot-copy-\(UUID().uuidString).json")
        try store.exportCopy(to: destination)
        #expect(try Data(contentsOf: destination) == Data(contentsOf: store.libraryURL))
    }
}
