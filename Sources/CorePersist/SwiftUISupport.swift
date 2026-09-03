#if canImport(SwiftUI)
import CoreData
import SwiftUI

private struct PersistentStoreKey: EnvironmentKey {
    static let defaultValue: PersistentStore? = nil
}

extension EnvironmentValues {
    /// The ``PersistentStore`` installed with ``SwiftUI/View/persistentStore(_:)``.
    public var persistentStore: PersistentStore? {
        get { self[PersistentStoreKey.self] }
        set { self[PersistentStoreKey.self] = newValue }
    }
}

extension View {
    /// Installs the store's view context and the store itself on the environment.
    public func persistentStore(_ store: PersistentStore) -> some View {
        environment(\.managedObjectContext, store.viewContext)
            .environment(\.persistentStore, store)
    }
}
#endif
