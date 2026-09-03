import CoreData
import Testing
@testable import CorePersist

@Suite(.serialized)
@MainActor
struct PersistentStoreTests {
    private func makeStore() throws -> PersistentStore {
        try PersistentStore(
            modelName: "CorePersistTests",
            model: TestModel.make(),
            configuration: .preview
        )
    }

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

    @Test
    func createFetchAndSave() throws {
        let store = try makeStore()
        try store.create(CPNote.self) { note in
            note.title = "Hello"
            note.createdAt = Date(timeIntervalSince1970: 1)
            note.isPinned = true
            note.views = 3
        }
        try store.save()

        let notes = try store.fetch(CPNote.self)
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Hello")
        #expect(notes.first?.views == 3)
        #expect(try store.count(CPNote.self) == 1)
    }

    @Test
    func keyPathQuery() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let pinned = try store.fetch(
            Query(CPNote.self)
                .where(\CPNote.isPinned == true)
                .sorted(by: \.title)
        )
        #expect(pinned.map(\.title) == ["Pinned"])
    }

    @Test
    func compoundPredicateAndContains() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let match = try store.fetch(
            Query(CPNote.self)
                .where(\CPNote.views > 1 && Where.contains(\.title, "in"))
        )
        #expect(match.map(\.title).sorted() == ["Inbox", "Pinned"])
    }

    @Test
    func optionalNilPredicate() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        let missingBody = try store.fetch(Query(CPNote.self).where(\CPNote.body == nil))
        #expect(missingBody.count == 2)
        #expect(Set(missingBody.map(\.title)) == Set(["Draft", "Inbox"]))
    }

    @Test
    func findOrCreate() throws {
        let store = try makeStore()
        let first = try store.findOrCreate(CPNote.self, where: \.title == "Unique") { note, isNew in
            #expect(isNew)
            note.title = "Unique"
            note.createdAt = Date()
        }
        let second = try store.findOrCreate(CPNote.self, where: \.title == "Unique") { _, isNew in
            #expect(!isNew)
        }
        #expect(first.objectID == second.objectID)
        #expect(try store.count(CPNote.self) == 1)
    }

    @Test
    func deleteAndRollback() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        try store.save()

        let draft = try store.first(Query(CPNote.self).where(\.title == "Draft"))
        store.delete(draft!)
        store.rollback()
        #expect(try store.count(CPNote.self) == 3)

        store.delete(draft!)
        try store.save()
        #expect(try store.count(CPNote.self) == 2)
    }

    @Test
    func limitOffsetAndSort() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        try store.save()
        let page = try store.fetch(
            Query(CPNote.self)
                .sorted(by: [NSSortDescriptor(key: "title", ascending: true)])
                .offset(1)
                .limit(1)
        )
        #expect(page.map(\.title) == ["Inbox"])
    }

    @Test
    func backgroundInsertReturnsObjectID() async throws {
        let (store, directory) = try makeSQLiteStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let objectID = try await store.performBackground { context in
            let note = CPNote(context: context)
            note.title = "Background"
            note.createdAt = Date()
            note.views = 9
            try context.obtainPermanentIDs(for: [note])
            return note.objectID
        }
        let note = try store.object(CPNote.self, id: objectID)
        #expect(note.title == "Background")
        #expect(note.views == 9)
    }

    @Test
    func batchDelete() async throws {
        let (store, directory) = try makeSQLiteStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try insertNotes(into: store)
        try store.save()

        let deleted = try await store.batchDelete(Query(CPNote.self).where(\.isPinned == false))
        #expect(deleted == 2)
        #expect(try store.fetch(CPNote.self).map(\.title) == ["Pinned"])
    }

    @Test
    func batchUpdate() async throws {
        let (store, directory) = try makeSQLiteStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try insertNotes(into: store)
        try store.save()

        let updated = try await store.batchUpdate(
            Query(CPNote.self).where(\.isPinned == true),
            properties: ["views": 100]
        )
        #expect(updated == 1)
        let pinned = try store.first(Query(CPNote.self).where(\.title == "Pinned"))
        #expect(pinned?.views == 100)
    }

    @Test
    func keyPathSort() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        try store.save()
        let titles = try store.fetch(Query(CPNote.self).sorted(by: \.title)).map(\.title)
        #expect(titles == ["Draft", "Inbox", "Pinned"])
    }

    @Test
    func observeFetchedResults() throws {
        let store = try makeStore()
        try insertNotes(into: store)
        try store.save()
        let results = try store.observe(Query(CPNote.self).sorted(by: \.title))
        #expect(results.count == 3)
        #expect(results.objects.map(\.title) == ["Draft", "Inbox", "Pinned"])
    }

    @Test
    func missingModelThrows() {
        #expect(throws: PersistenceError.modelNotFound("DoesNotExist")) {
            try PersistentStore(
                modelName: "DoesNotExist",
                bundle: Bundle(for: CPNote.self),
                configuration: .preview
            )
        }
    }
}
