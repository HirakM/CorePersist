import CoreData
import Foundation

/// A fluent, reusable fetch description for a managed object type.
///
/// ```swift
/// let recent = Query(Note.self)
///     .where(\Note.isPinned == true)
///     .sorted(by: \.createdAt, ascending: false)
///     .limit(20)
///
/// let notes = try recent.execute(in: context)
/// ```
public struct Query<Entity: NSManagedObject>: @unchecked Sendable {
    public private(set) var predicate: NSPredicate?
    public private(set) var sortDescriptors: [NSSortDescriptor] = []
    public private(set) var fetchLimit: Int = 0
    public private(set) var fetchOffset: Int = 0
    public private(set) var returnsObjectsAsFaults: Bool = true
    public private(set) var includesPendingChanges: Bool = true
    public private(set) var relationshipKeyPathsForPrefetching: [String] = []
    public private(set) var propertiesToFetch: [String]?
    public private(set) var resultType: NSFetchRequestResultType = .managedObjectResultType

    public init(_ type: Entity.Type = Entity.self) {}

    public func `where`(_ match: Where<Entity>) -> Query {
        combiningPredicate(match.predicate)
    }

    public func `where`(_ predicate: NSPredicate) -> Query {
        combiningPredicate(predicate)
    }

    public func `where`(_ format: String, _ args: any CVarArg...) -> Query {
        combiningPredicate(NSPredicate(format: format, argumentArray: args))
    }

    public func and(_ match: Where<Entity>) -> Query {
        self.where(match)
    }

    public func or(_ match: Where<Entity>) -> Query {
        var copy = self
        if let existing = copy.predicate {
            copy.predicate = NSCompoundPredicate(
                orPredicateWithSubpredicates: [existing, match.predicate]
            )
        } else {
            copy.predicate = match.predicate
        }
        return copy
    }

    public func sorted<Value>(by keyPath: KeyPath<Entity, Value>, ascending: Bool = true) -> Query {
        var copy = self
        copy.sortDescriptors.append(
            NSSortDescriptor(key: NSExpression(forKeyPath: keyPath).keyPath, ascending: ascending)
        )
        return copy
    }

    public func sorted(by descriptors: [NSSortDescriptor]) -> Query {
        var copy = self
        copy.sortDescriptors.append(contentsOf: descriptors)
        return copy
    }

    public func limit(_ count: Int) -> Query {
        var copy = self
        copy.fetchLimit = count
        return copy
    }

    public func offset(_ count: Int) -> Query {
        var copy = self
        copy.fetchOffset = count
        return copy
    }

    public func prefetching(_ keyPaths: String...) -> Query {
        var copy = self
        copy.relationshipKeyPathsForPrefetching.append(contentsOf: keyPaths)
        return copy
    }

    public func faults(_ returnsFaults: Bool) -> Query {
        var copy = self
        copy.returnsObjectsAsFaults = returnsFaults
        return copy
    }

    /// Builds an `NSFetchRequest` for this query. The request is not executed.
    public func fetchRequest() -> NSFetchRequest<Entity> {
        let request = NSFetchRequest<Entity>(entityName: Entity.corePersistEntityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors.isEmpty ? nil : sortDescriptors
        request.fetchLimit = fetchLimit
        request.fetchOffset = fetchOffset
        request.returnsObjectsAsFaults = returnsObjectsAsFaults
        request.includesPendingChanges = includesPendingChanges
        request.relationshipKeyPathsForPrefetching = relationshipKeyPathsForPrefetching
        request.propertiesToFetch = propertiesToFetch
        request.resultType = resultType
        return request
    }

    /// Executes on `context`. You must already be on that context's queue
    /// (`@MainActor` for the view context, or inside `perform` / ``PersistentStore/performBackground``).
    public func execute(in context: NSManagedObjectContext) throws -> [Entity] {
        try context.fetch(fetchRequest())
    }

    public func first(in context: NSManagedObjectContext) throws -> Entity? {
        try limit(1).execute(in: context).first
    }

    public func count(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: fetchRequest())
    }

    private func combiningPredicate(_ predicate: NSPredicate) -> Query {
        var copy = self
        if let existing = copy.predicate {
            copy.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [existing, predicate]
            )
        } else {
            copy.predicate = predicate
        }
        return copy
    }
}

extension NSManagedObject {
    static var corePersistEntityName: String {
        if let name = entity().name, !name.isEmpty {
            return name
        }
        let fullName = NSStringFromClass(self)
        return fullName.split(separator: ".").last.map(String.init) ?? fullName
    }
}
