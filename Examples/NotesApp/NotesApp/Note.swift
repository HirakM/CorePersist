import CoreData

@objc(Note)
final class Note: NSManagedObject {
    @NSManaged var title: String
    @NSManaged var createdAt: Date
    @NSManaged var isPinned: Bool
    @NSManaged var body: String?
}

extension Note: Identifiable {}
