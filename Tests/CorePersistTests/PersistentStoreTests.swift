import CoreData
import XCTest
@testable import CorePersist

@MainActor
private enum StoreTests {
    static func makeStore() throws -> PersistentStore {
        try PersistentStore(
            modelName: "CorePersistTests",
            model: TestModel.make(),
            configuration: .preview
        )
    }

    static func makeSQLiteStore() throws -> (PersistentStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorePersistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(
            modelName: "CorePersistTests",
            model: TestModel.make(),
            configuration: Configuration(storeName: "notes.sqlite", storeDirectory: directory)
        )
        return (store, directory)
    }

    static func insertNotes(into store: PersistentStore) throws {
        try store.create(CPNote.self) { note in
            note.title = "Pinned"
            note.createdAt = Date(timeIntervalSince1970: 3)
            note.isPinned = true
            note.views = 5
            note.body = "Keep this"
        }
        try store.create(CPNote.self) { note in
            note.title = "Draft"
            note.createdAt = Date(timeIntervalSince1970: 1)
            note.isPinned = false
            note.views = 0
        }
        try store.create(CPNote.self) { note in
            note.title = "Inbox"
            note.createdAt = Date(timeIntervalSince1970: 2)
            note.isPinned = false
            note.views = 2
        }
    }

    static func createFetchAndSave() throws {
        let store = try makeStore()
        try store.create(CPNote.self) { note in
            note.title = "Hello"
            note.createdAt = Date(timeIntervalSince1970: 1)
            note.isPinned = true
            note.views = 3
        }
        try store.save()

        let notes = try store.fetch(CPNote.self)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Hello")
        XCTAssertEqual(notes.first?.views, 3)
        XCTAssertEqual(try store.count(CPNote.self), 1)
    }

    static func keyPathQuery() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let pinned = try store.fetch(
            Query(CPNote.self)
                .where(\CPNote.isPinned == true)
                .sorted(by: \.title)
        )
        XCTAssertEqual(pinned.map(\.title), ["Pinned"])
    }

    static func compoundPredicateAndContains() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let match = try store.fetch(
            Query(CPNote.self)
                .where(\CPNote.views > 1 && Where.contains(\.title, "in"))
        )
        XCTAssertEqual(match.map(\.title).sorted(), ["Inbox", "Pinned"])
    }

    static func optionalNilPredicate() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let missingBody = try store.fetch(Query(CPNote.self).where(\CPNote.body == nil))
        XCTAssertEqual(missingBody.count, 2)
        XCTAssertEqual(Set(missingBody.map(\.title)), Set(["Draft", "Inbox"]))
    }

    static func findOrCreate() throws {
        let store = try makeStore()
        let first = try store.findOrCreate(CPNote.self, where: \.title == "Unique") { note, isNew in
            XCTAssertTrue(isNew)
            note.title = "Unique"
            note.createdAt = Date()
        }
        let second = try store.findOrCreate(CPNote.self, where: \.title == "Unique") { _, isNew in
            XCTAssertFalse(isNew)
        }
        XCTAssertEqual(first.objectID, second.objectID)
        XCTAssertEqual(try store.count(CPNote.self), 1)
    }

    static func deleteAndRollback() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        try store.save()

        let draft = try store.first(Query(CPNote.self).where(\.title == "Draft"))
        store.delete(draft!)
        store.rollback()
        XCTAssertEqual(try store.count(CPNote.self), 3)

        store.delete(draft!)
        try store.save()
        XCTAssertEqual(try store.count(CPNote.self), 2)
    }

    static func limitOffsetAndSort() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let page = try store.fetch(
            Query(CPNote.self)
                .sorted(by: \.title)
                .offset(1)
                .limit(1)
        )
        XCTAssertEqual(page.map(\.title), ["Inbox"])
    }

    static func backgroundInsertReturnsObjectID() async throws {
        let store = try makeStore()
        let objectID = try await store.performBackground { context in
            let note = CPNote(context: context)
            note.title = "Background"
            note.createdAt = Date()
            note.views = 9
            return note.objectID
        }
        let note = try store.object(CPNote.self, id: objectID)
        XCTAssertEqual(note.title, "Background")
        XCTAssertEqual(note.views, 9)
    }

    static func batchDelete() async throws {
        let (store, directory) = try makeSQLiteStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try insertNotes(into: store)
        try store.save()

        let deleted = try await store.batchDelete(Query(CPNote.self).where(\.isPinned == false))
        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(try store.fetch(CPNote.self).map(\.title), ["Pinned"])
    }

    static func batchUpdate() async throws {
        let (store, directory) = try makeSQLiteStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try insertNotes(into: store)
        try store.save()

        let updated = try await store.batchUpdate(
            Query(CPNote.self).where(\.isPinned == true),
            properties: ["views": 100]
        )
        XCTAssertEqual(updated, 1)
        let pinned = try store.first(Query(CPNote.self).where(\.title == "Pinned"))
        XCTAssertEqual(pinned?.views, 100)
    }

    static func observeFetchedResults() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        try store.save()
        let results = try store.observe(Query(CPNote.self).sorted(by: \.title))
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.objects.map(\.title), ["Draft", "Inbox", "Pinned"])
    }

    static func missingModelThrows() {
        XCTAssertThrowsError(
            try PersistentStore(
                modelName: "DoesNotExist",
                bundle: Bundle(for: CPNote.self),
                configuration: .preview
            )
        ) { error in
            XCTAssertEqual(error as? PersistenceError, .modelNotFound("DoesNotExist"))
        }
    }
}

final class PersistentStoreTests: XCTestCase {
    func testCreateFetchAndSave() async throws {
        try await StoreTests.createFetchAndSave()
    }

    func testKeyPathQuery() async throws {
        try await StoreTests.keyPathQuery()
    }

    func testCompoundPredicateAndContains() async throws {
        try await StoreTests.compoundPredicateAndContains()
    }

    func testOptionalNilPredicate() async throws {
        try await StoreTests.optionalNilPredicate()
    }

    func testFindOrCreate() async throws {
        try await StoreTests.findOrCreate()
    }

    func testDeleteAndRollback() async throws {
        try await StoreTests.deleteAndRollback()
    }

    func testLimitOffsetAndSort() async throws {
        try await StoreTests.limitOffsetAndSort()
    }

    func testBackgroundInsertReturnsObjectID() async throws {
        try await StoreTests.backgroundInsertReturnsObjectID()
    }

    func testBatchDelete() async throws {
        try await StoreTests.batchDelete()
    }

    func testBatchUpdate() async throws {
        try await StoreTests.batchUpdate()
    }

    func testObserveFetchedResults() async throws {
        try await StoreTests.observeFetchedResults()
    }

    func testMissingModelThrows() async throws {
        await StoreTests.missingModelThrows()
    }
}
