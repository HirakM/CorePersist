import CoreData
import Foundation

private struct SendableBox<T>: @unchecked Sendable {
    let value: T
}

extension PersistentStore {
    /// Deletes matching rows in the persistent store without loading them into memory.
    @discardableResult
    public func batchDelete<Entity: NSManagedObject>(
        _ query: Query<Entity>
    ) async throws -> Int {
        let objectIDs: [NSManagedObjectID] = try await performBackground { context in
            let fetchRequest = NSFetchRequest<any NSFetchRequestResult>(entityName: Entity.corePersistEntityName)
            fetchRequest.predicate = query.predicate
            fetchRequest.fetchLimit = query.fetchLimit
            fetchRequest.fetchOffset = query.fetchOffset
            let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            request.resultType = .resultTypeObjectIDs
            let result = try context.execute(request) as? NSBatchDeleteResult
            return result?.result as? [NSManagedObjectID] ?? []
        }
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
            into: [viewContext]
        )
        return objectIDs.count
    }

    /// Updates matching rows in the persistent store without loading them into memory.
    @discardableResult
    public func batchUpdate<Entity: NSManagedObject>(
        _ query: Query<Entity>,
        properties: [AnyHashable: Any]
    ) async throws -> Int {
        let payload = SendableBox(value: properties)
        let objectIDs: [NSManagedObjectID] = try await performBackground { context in
            let request = NSBatchUpdateRequest(entityName: Entity.corePersistEntityName)
            request.predicate = query.predicate
            request.propertiesToUpdate = payload.value
            request.resultType = .updatedObjectIDsResultType
            let result = try context.execute(request) as? NSBatchUpdateResult
            return result?.result as? [NSManagedObjectID] ?? []
        }
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSUpdatedObjectsKey: objectIDs],
            into: [viewContext]
        )
        return objectIDs.count
    }

    /// Inserts many rows from dictionaries of attribute names to values.
    @discardableResult
    public func batchInsert<Entity: NSManagedObject>(
        _ type: Entity.Type,
        objects: [[String: Any]]
    ) async throws -> Bool {
        let payload = SendableBox(value: objects)
        let objectIDs: [NSManagedObjectID] = try await performBackground { context in
            let request = NSBatchInsertRequest(entityName: type.corePersistEntityName, objects: payload.value)
            request.resultType = .objectIDs
            let result = try context.execute(request) as? NSBatchInsertResult
            return result?.result as? [NSManagedObjectID] ?? []
        }
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSInsertedObjectsKey: objectIDs],
            into: [viewContext]
        )
        return !objectIDs.isEmpty || objects.isEmpty
    }
}
