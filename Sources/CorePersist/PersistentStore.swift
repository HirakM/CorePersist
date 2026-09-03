import CoreData
import Foundation

/// A ready-to-use Core Data stack with a type-safe query API.
///
/// Create one store at app launch and share it through SwiftUI:
///
/// ```swift
/// @main
/// struct NotesApp: App {
///     @State private var store = PersistentStore.load(modelName: "Notes")
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .persistentStore(store)
///         }
///     }
/// }
/// ```
@MainActor
public final class PersistentStore {
    public let container: NSPersistentContainer
    public let configuration: Configuration
    public let modelName: String

    private var activeBackgroundTasks = 0

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// Loads a `.xcdatamodeld` compiled model from a bundle.
    public convenience init(
        modelName: String,
        bundle: Bundle = .main,
        configuration: Configuration = .default
    ) throws {
        let model = try Self.loadModel(named: modelName, in: bundle)
        try self.init(modelName: modelName, model: model, configuration: configuration)
    }

    /// Builds a stack from an already loaded `NSManagedObjectModel`.
    public init(
        modelName: String,
        model: NSManagedObjectModel,
        configuration: Configuration = .default
    ) throws {
        self.modelName = modelName
        self.configuration = configuration

        if configuration.usesCloudKit {
            container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: modelName, managedObjectModel: model)
        }

        let description = try Self.makeStoreDescription(
            modelName: modelName,
            configuration: configuration
        )
        container.persistentStoreDescriptions = [description]
        try Self.loadStores(on: container, configuration: configuration)
        Self.configureViewContext(container.viewContext, configuration: configuration)
    }

    /// Convenience loader for `App` entry points. Traps with a clear message if setup fails.
    public static func load(
        modelName: String,
        bundle: Bundle = .main,
        configuration: Configuration = .default
    ) -> PersistentStore {
        do {
            return try PersistentStore(
                modelName: modelName,
                bundle: bundle,
                configuration: configuration
            )
        } catch {
            fatalError("CorePersist failed to load model '\(modelName)': \(error)")
        }
    }

    /// In-memory store, optionally prefilled for SwiftUI previews.
    public static func preview(
        modelName: String,
        bundle: Bundle = .main,
        populate: ((NSManagedObjectContext) throws -> Void)? = nil
    ) -> PersistentStore {
        do {
            let store = try PersistentStore(
                modelName: modelName,
                bundle: bundle,
                configuration: .preview
            )
            if let populate {
                try populate(store.viewContext)
                try store.save()
            }
            return store
        } catch {
            fatalError("CorePersist preview store failed: \(error)")
        }
    }

    /// Saves the view context when it has changes.
    public func save() throws {
        guard viewContext.hasChanges else { return }
        try viewContext.save()
    }

    /// Discards unsaved view-context changes.
    public func rollback() {
        viewContext.rollback()
    }

    /// Creates a new private-queue context parented to the persistent store coordinator.
    ///
    /// Access it only with `context.perform` / `performAndWait`. Prefer ``performBackground`` so
    /// saves are merged back onto the view context on the correct queue.
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = configuration.mergePolicy.nsPolicy
        context.automaticallyMergesChangesFromParent = true
        context.transactionAuthor = configuration.transactionAuthor
        return context
    }

    /// Runs work on a private background context and saves if there are changes.
    ///
    /// Return `NSManagedObjectID` or value types from `work`. Do not hop managed objects across queues.
    @discardableResult
    public func performBackground<T: Sendable>(
        save: Bool = true,
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        activeBackgroundTasks += 1
        defer { activeBackgroundTasks -= 1 }

        let mergeKind = configuration.mergePolicy
        let author = configuration.transactionAuthor
        let container = self.container
        let viewContext = self.viewContext

        let outcome: (T, ContextChangeSet) = try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = mergeKind.nsPolicy
                context.automaticallyMergesChangesFromParent = true
                context.transactionAuthor = author
                do {
                    let result = try work(context)
                    var changes = ContextChangeSet()
                    if save, context.hasChanges {
                        try context.obtainPermanentIDs(for: Array(context.insertedObjects))
                        changes = ContextChangeSet(context: context)
                        try context.save()
                    }
                    continuation.resume(returning: (result, changes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if !outcome.1.isEmpty {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: outcome.1.userInfo,
                into: [viewContext]
            )
        }
        return outcome.0
    }

    /// Deletes every persistent store and loads a fresh one. Useful for logout / reset.
    public func destroyAndReload() throws {
        guard activeBackgroundTasks == 0 else {
            throw PersistenceError.storeBusy
        }

        for store in container.persistentStoreCoordinator.persistentStores {
            let url = store.url
            try container.persistentStoreCoordinator.remove(store)
            if let url, store.type != NSInMemoryStoreType {
                try container.persistentStoreCoordinator.destroyPersistentStore(
                    at: url,
                    ofType: store.type,
                    options: nil
                )
            }
        }

        let description = try Self.makeStoreDescription(
            modelName: modelName,
            configuration: configuration
        )
        container.persistentStoreDescriptions = [description]
        try Self.loadStores(on: container, configuration: configuration)
        viewContext.reset()
        Self.configureViewContext(viewContext, configuration: configuration)
    }
}

extension PersistentStore {
    static func loadModel(named name: String, in bundle: Bundle) throws -> NSManagedObjectModel {
        if let url = bundle.url(forResource: name, withExtension: "momd")
            ?? bundle.url(forResource: name, withExtension: "mom"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }

        throw PersistenceError.modelNotFound(name)
    }

    static func makeStoreDescription(
        modelName: String,
        configuration: Configuration
    ) throws -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        description.shouldMigrateStoreAutomatically = configuration.automaticallyMigratesStore
        description.shouldInferMappingModelAutomatically = configuration.infersMappingModel

        if configuration.inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.type = NSSQLiteStoreType
            description.url = try storeURL(modelName: modelName, configuration: configuration)
        }

        if configuration.usesHistoryTracking {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }

        if configuration.usesRemoteChangeNotifications {
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
        }

        if let identifier = configuration.cloudKitContainerIdentifier {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: identifier
            )
        }

        return description
    }

    static func storeURL(modelName: String, configuration: Configuration) throws -> URL {
        let fileName = configuration.storeName ?? "\(modelName).sqlite"

        if let group = configuration.appGroupIdentifier {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group
            ) else {
                throw PersistenceError.storeURLUnavailable
            }
            return containerURL.appendingPathComponent(fileName)
        }

        if let directory = configuration.storeDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        }

        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return folder.appendingPathComponent(fileName)
    }

    static func loadStores(
        on container: NSPersistentContainer,
        configuration: Configuration
    ) throws {
        do {
            try waitForPersistentStores(on: container)
        } catch {
            if configuration.destroysStoreOnFailedRecovery,
               let url = container.persistentStoreDescriptions.first?.url,
               !configuration.inMemory {
                try? FileManager.default.removeItem(at: url)
                let shm = URL(fileURLWithPath: url.path + "-shm")
                let wal = URL(fileURLWithPath: url.path + "-wal")
                try? FileManager.default.removeItem(at: shm)
                try? FileManager.default.removeItem(at: wal)
                try waitForPersistentStores(on: container)
            } else {
                throw error
            }
        }
    }

    /// `loadPersistentStores` invokes its handler on a background queue and may return
    /// before the store is ready. Waiting here makes init actually sequential.
    static func waitForPersistentStores(on container: NSPersistentContainer) throws {
        let lock = NSLock()
        let done = DispatchSemaphore(value: 0)
        var capturedError: (any Error)?

        container.loadPersistentStores { _, error in
            lock.lock()
            capturedError = error
            lock.unlock()
            done.signal()
        }
        done.wait()

        lock.lock()
        defer { lock.unlock() }
        if let capturedError {
            throw PersistenceError.loadFailed(capturedError.localizedDescription)
        }
    }

    static func configureViewContext(
        _ context: NSManagedObjectContext,
        configuration: Configuration
    ) {
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = configuration.mergePolicy.nsPolicy
        context.shouldDeleteInaccessibleFaults = true
        context.transactionAuthor = configuration.transactionAuthor
        context.name = "CorePersist.viewContext"
    }
}

private struct ContextChangeSet: Sendable {
    var inserted: [NSManagedObjectID] = []
    var updated: [NSManagedObjectID] = []
    var deleted: [NSManagedObjectID] = []

    init() {}

    init(context: NSManagedObjectContext) {
        inserted = context.insertedObjects.map(\.objectID)
        updated = context.updatedObjects.map(\.objectID)
        deleted = context.deletedObjects.map(\.objectID)
    }

    var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }

    var userInfo: [AnyHashable: Any] {
        [
            NSInsertedObjectsKey: inserted,
            NSUpdatedObjectsKey: updated,
            NSDeletedObjectsKey: deleted
        ]
    }
}
