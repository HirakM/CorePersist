import CoreData
import Foundation

/// Options that control how ``PersistentStore`` creates and loads a Core Data stack.
public struct Configuration: Sendable, Equatable {
    /// When `true`, uses an in-memory store. Ideal for SwiftUI previews and tests.
    public var inMemory: Bool

    /// File name without path, for example `"MyApp.sqlite"`. Defaults to `"<modelName>.sqlite"`.
    public var storeName: String?

    /// App Group identifier so the store can be shared with extensions and widgets.
    public var appGroupIdentifier: String?

    /// iCloud container identifier. When set, the stack uses `NSPersistentCloudKitContainer`.
    public var cloudKitContainerIdentifier: String?

    /// Automatically migrates the store when the model changes.
    public var automaticallyMigratesStore: Bool

    /// Infers a mapping model when no custom mapping is provided.
    public var infersMappingModel: Bool

    /// Enables persistent history tracking. Implied when CloudKit is enabled.
    public var persistentHistoryTracking: Bool

    /// Posts remote-change notifications. Implied when CloudKit is enabled.
    public var remoteChangeNotifications: Bool

    /// Merge policy applied to the view context and background contexts.
    public var mergePolicy: MergePolicy

    /// Optional author written into persistent history transactions.
    public var transactionAuthor: String?

    /// When `true`, deletes a corrupted on-disk store and retries once. Useful in DEBUG.
    public var destroysStoreOnFailedRecovery: Bool

    public init(
        inMemory: Bool = false,
        storeName: String? = nil,
        appGroupIdentifier: String? = nil,
        cloudKitContainerIdentifier: String? = nil,
        automaticallyMigratesStore: Bool = true,
        infersMappingModel: Bool = true,
        persistentHistoryTracking: Bool = false,
        remoteChangeNotifications: Bool = false,
        mergePolicy: MergePolicy = .objectTrump,
        transactionAuthor: String? = nil,
        destroysStoreOnFailedRecovery: Bool = false
    ) {
        self.inMemory = inMemory
        self.storeName = storeName
        self.appGroupIdentifier = appGroupIdentifier
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.automaticallyMigratesStore = automaticallyMigratesStore
        self.infersMappingModel = infersMappingModel
        self.persistentHistoryTracking = persistentHistoryTracking
        self.remoteChangeNotifications = remoteChangeNotifications
        self.mergePolicy = mergePolicy
        self.transactionAuthor = transactionAuthor
        self.destroysStoreOnFailedRecovery = destroysStoreOnFailedRecovery
    }

    /// On-disk SQLite store with lightweight migration enabled.
    public static let `default` = Configuration()

    /// In-memory store for previews and unit tests.
    public static let preview = Configuration(inMemory: true)

    public enum MergePolicy: Sendable, Equatable {
        /// Fail when there are conflicting changes.
        case error
        /// In-memory changes overwrite the store.
        case overwrite
        /// Discard in-memory changes that conflict with the store.
        case rollback
        /// Property-by-property, in-memory object wins. Best default for apps.
        case objectTrump
        /// Property-by-property, persistent store wins.
        case storeTrump

        var nsPolicy: NSMergePolicy {
            switch self {
            case .error: NSMergePolicy.error
            case .overwrite: NSMergePolicy.overwrite
            case .rollback: NSMergePolicy.rollback
            case .objectTrump: NSMergePolicy.mergeByPropertyObjectTrump
            case .storeTrump: NSMergePolicy.mergeByPropertyStoreTrump
            }
        }
    }

    var usesCloudKit: Bool { cloudKitContainerIdentifier != nil }

    var usesHistoryTracking: Bool {
        persistentHistoryTracking || usesCloudKit
    }

    var usesRemoteChangeNotifications: Bool {
        remoteChangeNotifications || usesCloudKit
    }
}
