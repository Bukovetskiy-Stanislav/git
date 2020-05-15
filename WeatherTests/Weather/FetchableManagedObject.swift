
import Foundation
import CoreData

protocol FetchableManagedObject {

    associatedtype FetchableType: NSManagedObject = Self

    static func entityName() -> String
    static func insertNewObject(context: NSManagedObjectContext) -> FetchableType
    static func objectsInContext(context: NSManagedObjectContext, predicate: NSPredicate?, sortedBy: String?, ascending: Bool) throws -> [FetchableType]
    static func singleObjectInContext(context: NSManagedObjectContext, predicate: NSPredicate?, sortedBy: String?, ascending: Bool) throws -> FetchableType?
    static func objectCountInContext(context: NSManagedObjectContext, predicate: NSPredicate?) -> Int
    static func fetchRequest(context: NSManagedObjectContext, predicate: NSPredicate?, sortedBy: String?, ascending: Bool) -> NSFetchRequest

}

extension FetchableManagedObject where Self: NSManagedObject, FetchableType == Self {

    static func insertNewObject(context: NSManagedObjectContext) -> FetchableType {
        let newObject = NSEntityDescription.insertNewObjectForEntityForName(entityName(), inManagedObjectContext: context)
        return newObject as! FetchableType
    }

    static func singleObjectInContext(context: NSManagedObjectContext, predicate: NSPredicate? = nil, sortedBy: String? = nil, ascending: Bool = false) throws -> FetchableType? {
        let managedObjects: [FetchableType] = try objectsInContext(context, predicate: predicate, sortedBy: sortedBy, ascending: ascending)
        guard managedObjects.count > 0 else {
            return nil
        }
        return managedObjects.first
    }

    static func objectCountInContext(context: NSManagedObjectContext, predicate: NSPredicate? = nil) -> Int {
        let request = fetchRequest(context, predicate: predicate)
        let error: NSErrorPointer = nil
        let count = context.countForFetchRequest(request, error: error)
        guard error == nil else {
            NSLog("Error retrieving data %@, %@", error, error.debugDescription)
            return 0
        }
        return count
    }

    static func objectsInContext(context: NSManagedObjectContext, predicate: NSPredicate? = nil, sortedBy: String? = nil, ascending: Bool = false) throws -> [FetchableType] {
        let request = fetchRequest(context, predicate: predicate, sortedBy: sortedBy, ascending: ascending)
        let fetchResults = try context.executeFetchRequest(request)
        return fetchResults as! [FetchableType]
    }

    static func fetchRequest(context: NSManagedObjectContext, predicate: NSPredicate? = nil, sortedBy: String? = nil, ascending: Bool = false) -> NSFetchRequest {
        let request = NSFetchRequest()
        let entity = NSEntityDescription.entityForName(entityName(), inManagedObjectContext: context)
        request.entity = entity
        if predicate != nil {
            request.predicate = predicate
        }
        if sortedBy != nil {
            let sort = NSSortDescriptor(key: sortedBy, ascending: ascending)
            let sortDescriptors = [sort]
            request.sortDescriptors = sortDescriptors
        }
        return request
    }

}