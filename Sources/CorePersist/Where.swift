import CoreData
import Foundation

/// Type-safe `NSPredicate` builder using `KeyPath` operators.
///
/// ```swift
/// let match = \Note.isPinned == true && \Note.views > 10
/// let notes = try store.fetch(Query(Note.self).where(match))
/// ```
public struct Where<Entity: NSManagedObject>: @unchecked Sendable {
    public let predicate: NSPredicate

    public init(_ predicate: NSPredicate) {
        self.predicate = predicate
    }

    public static func contains(
        _ keyPath: KeyPath<Entity, String>,
        _ substring: String,
        caseInsensitive: Bool = true
    ) -> Where {
        Where(compare(keyPath, .contains, substring, options: caseInsensitive ? .caseInsensitive : []))
    }

    public static func contains(
        _ keyPath: KeyPath<Entity, String?>,
        _ substring: String,
        caseInsensitive: Bool = true
    ) -> Where {
        Where(compare(keyPath, .contains, substring, options: caseInsensitive ? .caseInsensitive : []))
    }

    public static func beginsWith(
        _ keyPath: KeyPath<Entity, String>,
        _ prefix: String,
        caseInsensitive: Bool = true
    ) -> Where {
        Where(compare(keyPath, .beginsWith, prefix, options: caseInsensitive ? .caseInsensitive : []))
    }

    public static func endsWith(
        _ keyPath: KeyPath<Entity, String>,
        _ suffix: String,
        caseInsensitive: Bool = true
    ) -> Where {
        Where(compare(keyPath, .endsWith, suffix, options: caseInsensitive ? .caseInsensitive : []))
    }

    public static func `in`<Value>(_ keyPath: KeyPath<Entity, Value>, _ values: [Value]) -> Where {
        Where(
            NSComparisonPredicate(
                leftExpression: NSExpression(forKeyPath: keyPath),
                rightExpression: NSExpression(forConstantValue: values),
                modifier: .direct,
                type: .in,
                options: []
            )
        )
    }

    public static func between<Value>(
        _ keyPath: KeyPath<Entity, Value>,
        _ range: ClosedRange<Value>
    ) -> Where where Value: Comparable {
        let key = NSExpression(forKeyPath: keyPath).keyPath
        return Where(
            NSPredicate(
                format: "%K BETWEEN {%@, %@}",
                argumentArray: [key, range.lowerBound, range.upperBound]
            )
        )
    }

    public static func isNil<Value>(_ keyPath: KeyPath<Entity, Value?>) -> Where {
        let key = NSExpression(forKeyPath: keyPath).keyPath
        return Where(NSPredicate(format: "%K == nil", key))
    }

    public static func isNotNil<Value>(_ keyPath: KeyPath<Entity, Value?>) -> Where {
        let key = NSExpression(forKeyPath: keyPath).keyPath
        return Where(NSPredicate(format: "%K != nil", key))
    }
}

public func == <Entity: NSManagedObject, Value>(
    lhs: KeyPath<Entity, Value>,
    rhs: Value
) -> Where<Entity> {
    Where(compare(lhs, .equalTo, rhs))
}

public func == <Entity: NSManagedObject, Value>(
    lhs: KeyPath<Entity, Value?>,
    rhs: Value?
) -> Where<Entity> {
    if let rhs {
        return Where(compare(lhs, .equalTo, rhs))
    }
    return .isNil(lhs)
}

public func != <Entity: NSManagedObject, Value>(
    lhs: KeyPath<Entity, Value>,
    rhs: Value
) -> Where<Entity> {
    Where(compare(lhs, .notEqualTo, rhs))
}

public func != <Entity: NSManagedObject, Value>(
    lhs: KeyPath<Entity, Value?>,
    rhs: Value?
) -> Where<Entity> {
    if let rhs {
        return Where(compare(lhs, .notEqualTo, rhs))
    }
    return .isNotNil(lhs)
}

public func > <Entity: NSManagedObject, Value: Comparable>(
    lhs: KeyPath<Entity, Value>,
    rhs: Value
) -> Where<Entity> {
    Where(compare(lhs, .greaterThan, rhs))
}

public func >= <Entity: NSManagedObject, Value: Comparable>(
    lhs: KeyPath<Entity, Value>,
    rhs: Value
) -> Where<Entity> {
    Where(compare(lhs, .greaterThanOrEqualTo, rhs))
}

public func < <Entity: NSManagedObject, Value: Comparable>(
    lhs: KeyPath<Entity, Value>,
    rhs: Value
) -> Where<Entity> {
    Where(compare(lhs, .lessThan, rhs))
}

public func <= <Entity: NSManagedObject, Value: Comparable>(
    lhs: KeyPath<Entity, Value>,
    rhs: Value
) -> Where<Entity> {
    Where(compare(lhs, .lessThanOrEqualTo, rhs))
}

public func && <Entity: NSManagedObject>(
    lhs: Where<Entity>,
    rhs: Where<Entity>
) -> Where<Entity> {
    Where(NSCompoundPredicate(andPredicateWithSubpredicates: [lhs.predicate, rhs.predicate]))
}

public func || <Entity: NSManagedObject>(
    lhs: Where<Entity>,
    rhs: Where<Entity>
) -> Where<Entity> {
    Where(NSCompoundPredicate(orPredicateWithSubpredicates: [lhs.predicate, rhs.predicate]))
}

public prefix func ! <Entity: NSManagedObject>(value: Where<Entity>) -> Where<Entity> {
    Where(NSCompoundPredicate(notPredicateWithSubpredicate: value.predicate))
}

func compare<Root, Value>(
    _ keyPath: KeyPath<Root, Value>,
    _ op: NSComparisonPredicate.Operator,
    _ value: Any?,
    options: NSComparisonPredicate.Options = []
) -> NSPredicate {
    NSComparisonPredicate(
        leftExpression: NSExpression(forKeyPath: keyPath),
        rightExpression: NSExpression(forConstantValue: value),
        modifier: .direct,
        type: op,
        options: options
    )
}
