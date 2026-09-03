import CoreData
import XCTest
@testable import CorePersist

final class PersistentStoreTests: XCTestCase {
    @MainActor
    private func makeStore() throws -> PersistentStore {
        try PersistentStore(
            modelName: "CorePersistTests",
            model: TestModel.make(),
            configuration: .preview
        )
    }

    @MainActor
    private func makeSQLiteStore() throws -> (PersistentStore, URL) {
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

    func testCreateFetchAndSave() async throws {
        try await MainActor.run {
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
    }

    func testKeyPathQuery() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try insertNotes(into: store)

            let pinned = try store.fetch(
                Query(CPNote.self)
                    .where(\CPNote.isPinned == true)
                    .sorted(by: \.title)
            )

            XCTAssertEqual(pinned.map(\.title), ["Pinned"])
        }
    }

    func testCompoundPredicateAndContains() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try insertNotes(into: store)

            let match = try store.fetch(
                Query(CPNote.self)
                    .where(\CPNote.views > 1 && Where.contains(\.title, "in"))
            )

            XCTAssertEqual(match.map(\.title).sorted(), ["Inbox", "Pinned"])
        }
    }

    func testOptionalNilPredicate() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try insertNotes(into: store)

            let missingBody = try store.fetch(Query(CPNote.self).where(\CPNote.body == nil))
            XCTAssertEqual(missingBody.count, 2)
            XCTAssertEqual(Set(missingBody.map(\.title)), Set(["Draft", "Inbox"]))
        }
    }

    func testFindOrCreate() async throws {
        try await MainActor.run {
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
    }

    func testDeleteAndRollback() async throws {
        try await MainActor.run {
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
    }

    func testLimitOffsetAndSort() async throws {
        try await MainActor.run {
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
    }

    func testBackgroundInsertReturnsObjectID() async throws {
        let store = try await MainActor.run { try makeStore() }

        let objectID = try await store.performBackground { context in
            let note = CPNote(context: context)
            note.title = "Background"
            note.createdAt = Date()
            note.views = 9
            return note.objectID
        }

        try await MainActor.run {
            let note = try store.object(CPNote.self, id: objectID)
            XCTAssertEqual(note.title, "Background")
            XCTAssertEqual(note.views, 9)
        }
    }

    func testBatchDelete() async throws {
        let (store, directory) = try await MainActor.run { try makeSQLiteStore() }
        defer { try? FileManager.default.removeItem(at: directory) }

        try await MainActor.run {
            try insertNotes(into: store)
            try store.save()
        }

        let deleted = try await store.batchDelete(Query(CPNote.self).where(\.isPinned == false))

        try await MainActor.run {
            XCTAssertEqual(deleted, 2)
            XCTAssertEqual(try store.fetch(CPNote.self).map(\.title), ["Pinned"])
        }
    }

    func testBatchUpdate() async throws {
        let (store, directory) = try await MainActor.run { try makeSQLiteStore() }
        defer { try? FileManager.default.removeItem(at: directory) }

        try await MainActor.run {
            try insertNotes(into: store)
            try store.save()
        }

        let updated = try await store.batchUpdate(
            Query(CPNote.self).where(\.isPinned == true),
            properties: ["views": 100]
        )

        try await MainActor.run {
            XCTAssertEqual(updated, 1)
            let pinned = try store.first(Query(CPNote.self).where(\.title == "Pinned"))
            XCTAssertEqual(pinned?.views, 100)
        }
    }

    func testObserveFetchedResults() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try insertNotes(into: store)
            try store.save()

            let results = try store.observe(
                Query(CPNote.self).sorted(by: \.title)
            )

            XCTAssertEqual(results.count, 3)
            XCTAssertEqual(results.objects.map(\.title), ["Draft", "Inbox", "Pinned"])
        }
    }

    func testMissingModelThrows() async throws {
        try await MainActor.run {
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

    @MainActor
    private func insertNotes(into store: PersistentStore) throws {
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
}
