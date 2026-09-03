import CoreData
import Foundation

@objc(CPNote)
final class CPNote: NSManagedObject {
    @NSManaged var title: String
    @NSManaged var createdAt: Date
    @NSManaged var isPinned: Bool
    @NSManaged var views: Int64
    @NSManaged var body: String?
}

enum TestModel {
    static func make() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "CPNote"
        entity.managedObjectClassName = "CPNote"

        func attribute(
            _ name: String,
            type: NSAttributeType,
            optional: Bool = false,
            defaultValue: Any? = nil
        ) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            attribute.defaultValue = defaultValue
            return attribute
        }

        entity.properties = [
            attribute("title", type: .stringAttributeType, defaultValue: ""),
            attribute("createdAt", type: .dateAttributeType, defaultValue: Date(timeIntervalSince1970: 0)),
            attribute("isPinned", type: .booleanAttributeType, defaultValue: false),
            attribute("views", type: .integer64AttributeType, defaultValue: 0),
            attribute("body", type: .stringAttributeType, optional: true)
        ]

        model.entities = [entity]
        return model
    }
}
