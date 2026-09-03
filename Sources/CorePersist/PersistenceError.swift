import CoreData
import Foundation

/// Errors thrown by ``PersistentStore`` and related CorePersist APIs.
public enum PersistenceError: Error, Equatable, LocalizedError, Sendable {
    case modelNotFound(String)
    case storeURLUnavailable
    case loadFailed(String)
    case objectNotFound
    case invalidObjectType(expected: String)
    case missingSortDescriptors
    case batchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            "Core Data model '\(name)' was not found in the bundle."
        case .storeURLUnavailable:
            "Could not resolve a URL for the persistent store."
        case .loadFailed(let message):
            "Failed to load the persistent store: \(message)"
        case .objectNotFound:
            "No managed object exists for the given ID."
        case .invalidObjectType(let expected):
            "The object is not of expected type \(expected)."
        case .missingSortDescriptors:
            "NSFetchedResultsController requires at least one sort descriptor."
        case .batchFailed(let message):
            "Batch operation failed: \(message)"
        }
    }
}
