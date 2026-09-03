import CoreData
import Foundation

extension PersistentStore {
    /// Inserts a new object into the view context. Call ``save()`` to persist.
    @discardableResult
    public func create<Entity: NSManagedObject>(
        _ type: Entity.Type,
        configure: (Entity) throws -> Void = { _ in }
    ) throws -> Entity {
        let object = Entity(context: viewContext)
        try configure(object)
        return object
    }

    /// Fetches objects matching `query` on the view context.
    public func fetch<Entity: NSManagedObject>(_ query: Query<Entity>) throws -> [Entity] {
        try query.execute(in: viewContext)
    }

    /// Fetches every object of `type`.
    public func fetch<Entity: NSManagedObject>(_ type: Entity.Type) throws -> [Entity] {
        try fetch(Query(type))
    }

    public func first<Entity: NSManagedObject>(_ query: Query<Entity>) throws -> Entity? {
        try query.first(in: viewContext)
    }

    public func count<Entity: NSManagedObject>(_ query: Query<Entity>) throws -> Int {
        try query.count(in: viewContext)
    }

    public func count<Entity: NSManagedObject>(_ type: Entity.Type) throws -> Int {
        try count(Query(type))
    }

    /// Returns an existing object or creates one, then runs `configure`.
    @discardableResult
    public func findOrCreate<Entity: NSManagedObject>(
        _ type: Entity.Type,
        where match: Where<Entity>,
        configure: (_ object: Entity, _ isNew: Bool) throws -> Void = { _, _ in }
    ) throws -> Entity {
        if let existing = try first(Query(type).where(match)) {
            try configure(existing, false)
            return existing
        }
        let created = Entity(context: viewContext)
        try configure(created, true)
        return created
    }

    public func object<Entity: NSManagedObject>(
        _ type: Entity.Type,
        id: NSManagedObjectID
    ) throws -> Entity {
        let object = try viewContext.existingObject(with: id)
        guard let typed = object as? Entity else {
            throw PersistenceError.invalidObjectType(expected: String(describing: Entity.self))
        }
        return typed
    }

    public func object<Entity: NSManagedObject>(
        _ type: Entity.Type,
        from backgroundID: NSManagedObjectID
    ) -> Entity? {
        try? object(type, id: backgroundID)
    }

    public func delete(_ object: NSManagedObject) {
        viewContext.delete(object)
    }

    public func delete<Entity: NSManagedObject>(_ objects: [Entity]) {
        objects.forEach(viewContext.delete)
    }

    /// Deletes matching objects through the view context. Prefer ``batchDelete`` for large sets.
    public func delete<Entity: NSManagedObject>(_ query: Query<Entity>) throws {
        try fetch(query).forEach(viewContext.delete)
    }
}
