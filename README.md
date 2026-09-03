# CorePersist

A small Core Data stack for Swift apps. One object to load the store, query with `KeyPath`s instead of predicate strings, and the usual extras that every iOS project rewrites: SwiftUI, CloudKit, App Groups, background saves, and in-memory previews.

[![CI](https://github.com/HirakM/CorePersist/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/HirakM/CorePersist/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20|%20macOS%2014%20|%20tvOS%2017%20|%20watchOS%2010%20|%20visionOS-blue)](Package.swift)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Why this exists

Core Data is powerful. The boilerplate around it is not:

- `NSPersistentContainer` vs `NSPersistentCloudKitContainer`
- view context merge policy and `automaticallyMergesChangesFromParent`
- App Group store URLs for widgets and extensions
- `NSPredicate(format:)` typos
- hopping work to a background context without leaking `NSManagedObject` across queues
- an in-memory store for tests and SwiftUI previews

CorePersist is that layer. It is not a new database and it is not SwiftData. Your `.xcdatamodeld` and `NSManagedObject` subclasses stay the same.

## Install

Add the package in Xcode (**File → Add Package Dependencies…**) or in `Package.swift`:

```swift
.package(url: "https://github.com/HirakM/CorePersist.git", from: "1.0.0")
```

```swift
.product(name: "CorePersist", package: "CorePersist")
```

Minimum platforms: iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1.

## Example app

Clone the repo and open `Examples/NotesApp/NotesApp.xcodeproj` in Xcode, then run the **NotesApp** scheme on a simulator. It is a small notes list that uses `PersistentStore.load`, `.persistentStore(_:)`, `create`, `save`, and `delete`.

## Quick start

```swift
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
```

`persistentStore(_:)` sets both the store and `\.managedObjectContext`, so `@FetchRequest` keeps working.

```swift
struct ContentView: View {
    @Environment(\.persistentStore) private var store
    @FetchRequest(sortDescriptors: [SortDescriptor(\Note.createdAt, order: .reverse)])
    private var notes: FetchedResults<Note>

    var body: some View {
        List(notes) { note in
            Text(note.title)
        }
        .toolbar {
            Button("Add") {
                try? store?.create(Note.self) { note in
                    note.title = "New note"
                    note.createdAt = Date()
                }
                try? store?.save()
            }
        }
    }
}
```

## Queries without predicate strings

```swift
let recentPinned = try store.fetch(
    Query(Note.self)
        .where(\Note.isPinned == true && \Note.createdAt > lastWeek)
        .sorted(by: \.createdAt, ascending: false)
        .limit(20)
)

let search = try store.fetch(
    Query(Note.self).where(.contains(\.title, "invoice"))
)

let drafts = try store.fetch(
    Query(Note.self).where(\Note.body == nil)
)
```

Supported operators: `==`, `!=`, `>`, `>=`, `<`, `<=`, `&&`, `||`, `!`.

Helpers on `Where`: `.contains`, `.beginsWith`, `.endsWith`, `.in`, `.between`, `.isNil`, `.isNotNil`.

Raw `NSPredicate` still works when you need it:

```swift
Query(Note.self).where("views >= %d", 10)
```

`Query` also runs on any context, including background ones:

```swift
let ids = try await store.performBackground { context in
    try Query(Note.self)
        .where(\Note.isPinned == false)
        .execute(in: context)
        .map(\.objectID)
}
```

## Create, find, delete

```swift
try store.create(Note.self) { note in
    note.title = "Shipping"
    note.createdAt = .now
}

try store.findOrCreate(Note.self, where: \.title == "Inbox") { note, isNew in
    if isNew { note.createdAt = .now }
}

store.delete(note)
try store.save()
```

## Background work

`performBackground` uses a private-queue context and saves automatically. Return object IDs or value types — never the managed object itself.

```swift
let id = try await store.performBackground { context in
    let note = Note(context: context)
    note.title = "Imported"
    note.createdAt = .now
    return note.objectID
}

let note = try store.object(Note.self, id: id)
```

Large updates skip the object graph:

```swift
try await store.batchDelete(Query(Note.self).where(\.isPinned == false))
try await store.batchUpdate(Query(Note.self), properties: ["isPinned": false])
try await store.batchInsert(Note.self, objects: [
    ["title": "One", "createdAt": Date()],
    ["title": "Two", "createdAt": Date()]
])
```

## CloudKit, widgets, tests

```swift
let store = try PersistentStore(
    modelName: "Notes",
    configuration: Configuration(
        appGroupIdentifier: "group.com.example.notes",
        cloudKitContainerIdentifier: "iCloud.com.example.notes",
        transactionAuthor: "app"
    )
)
```

CloudKit turns on persistent history tracking and remote-change notifications for you.

```swift
// Unit tests
let store = try PersistentStore(
    modelName: "Notes",
    model: MyModel.make(),          // or load from a test bundle
    configuration: .preview         // in-memory
)

// SwiftUI previews
#Preview {
    ContentView()
        .persistentStore(.preview(modelName: "Notes") { context in
            let note = Note(context: context)
            note.title = "Sample"
            note.createdAt = .now
        })
}
```

## Live results

`@FetchRequest` is still the right SwiftUI default. When you want an observable object (UIKit, or a view model):

```swift
let results: ObservedQuery<Note> = try store.observe(
    Query(Note.self).sorted(by: \.createdAt, ascending: false)
)

results.objects  // updates as the context changes
```

## Configuration

| Option | Default | Purpose |
| --- | --- | --- |
| `inMemory` | `false` | Tests and previews |
| `storeName` | `"<model>.sqlite"` | File name |
| `storeDirectory` | Application Support | Custom on-disk folder |
| `appGroupIdentifier` | `nil` | Share with extensions |
| `cloudKitContainerIdentifier` | `nil` | `NSPersistentCloudKitContainer` |
| `automaticallyMigratesStore` | `true` | Lightweight migration |
| `infersMappingModel` | `true` | Infer mapping models |
| `persistentHistoryTracking` | CloudKit implies `true` | History tokens |
| `mergePolicy` | `.objectTrump` | In-memory properties win |
| `transactionAuthor` | `nil` | History author |
| `destroysStoreOnFailedRecovery` | `false` | Delete a corrupt store and retry |

`store.destroyAndReload()` wipes the store and loads a new one (logout / reset).

## Concurrency

`PersistentStore` is `@MainActor`. That is the thread-safety model:

- View-context reads and writes (`fetch`, `create`, `save`, `delete`) only run on the main actor.
- Background work goes through `performBackground`. Return `NSManagedObjectID` or value types — never the managed object.
- After a background save, changes are merged into the view context before `performBackground` returns, so a following `store.object(_:id:)` does not race.
- `destroyAndReload()` throws `PersistenceError.storeBusy` if background work is still running.
- `ObservedQuery` only accepts the main-queue view context.
- `Query.execute(in:)` does not hop threads. Use the context you are already on.

Do not use a managed object on a different queue than the context that owns it. That is a Core Data rule this package cannot fully police if you grab `viewContext` or `newBackgroundContext()` and call Core Data APIs yourself.

## Requirements

- Xcode 16+
- Swift 6
- A compiled Core Data model (`.xcdatamodeld`) in your app target

## License

MIT. See [LICENSE](LICENSE).
