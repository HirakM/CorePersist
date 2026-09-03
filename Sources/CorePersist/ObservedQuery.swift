import CoreData
import Foundation
import Observation

/// Live query results driven by `NSFetchedResultsController`.
///
/// Named separately from SwiftUI's `FetchedResults` to avoid import clashes.
/// Hold this object as `@State` (or a stored property) so the fetch stays active:
///
/// ```swift
/// @State private var notes: ObservedQuery<Note>
///
/// init(store: PersistentStore) {
///     _notes = State(
///         initialValue: try! store.observe(
///             Query(Note.self).sorted(by: \.createdAt, ascending: false)
///         )
///     )
/// }
/// ```
@Observable
public final class ObservedQuery<Entity: NSManagedObject> {
    public private(set) var objects: [Entity]
    public private(set) var error: (any Error)?

    public var isEmpty: Bool { objects.isEmpty }
    public var count: Int { objects.count }

    private let controller: NSFetchedResultsController<Entity>
    private let proxy: DelegateProxy

    public init(query: Query<Entity>, context: NSManagedObjectContext, sectionNameKeyPath: String? = nil) throws {
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            throw PersistenceError.requiresMainQueueContext
        }
        guard !query.sortDescriptors.isEmpty else {
            throw PersistenceError.missingSortDescriptors
        }

        let controller = NSFetchedResultsController(
            fetchRequest: query.fetchRequest(),
            managedObjectContext: context,
            sectionNameKeyPath: sectionNameKeyPath,
            cacheName: nil
        )
        self.controller = controller
        self.proxy = DelegateProxy()
        self.objects = []
        self.proxy.owner = self
        controller.delegate = proxy
        try controller.performFetch()
        self.objects = controller.fetchedObjects ?? []
    }

    public subscript(index: Int) -> Entity {
        objects[index]
    }
}

extension PersistentStore {
    public func observe<Entity: NSManagedObject>(
        _ query: Query<Entity>,
        sectionNameKeyPath: String? = nil
    ) throws -> ObservedQuery<Entity> {
        try ObservedQuery(query: query, context: viewContext, sectionNameKeyPath: sectionNameKeyPath)
    }
}

extension ObservedQuery {
    fileprivate final class DelegateProxy: NSObject, NSFetchedResultsControllerDelegate {
        weak var owner: ObservedQuery?

        func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
            let objects = (controller.fetchedObjects as? [Entity]) ?? []
            precondition(
                Thread.isMainThread,
                "ObservedQuery received an FRC update off the main queue."
            )
            owner?.objects = objects
        }
    }
}
