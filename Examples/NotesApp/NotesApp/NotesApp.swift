import CorePersist
import SwiftUI

@main
struct NotesApp: App {
    @State private var store = PersistentStore.load(modelName: "Notes")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentStore(store)
        }
    }
}
