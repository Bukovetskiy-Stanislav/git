

import Foundation
import CoreData

class WDCoreData {

    enum StoreType {
        case InMemory
        case SQLite
        var storeTypeValue: String {
            switch self {
            case .InMemory: return NSInMemoryStoreType
            case .SQLite: return NSSQLiteStoreType
            }
        }
    }

    let storeType: StoreType

    init(storeType: StoreType = .SQLite) {

        // Config
        self.storeType = storeType

        // Listen for notifications
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(WDCoreData.managedObjectContextDidSaveNotification(_:)), name:
            NSManagedObjectContextDidSaveNotification, object: nil)

    }

    deinit {

        // Remove observer
        NSNotificationCenter.defaultCenter().removeObserver(self)

    }

    // MARK: - Core Data Stack

    lazy var applicationDocumentsDirectory: NSURL = {
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls.last!
    }()

    lazy var managedObjectModel: NSManagedObjectModel = {
        let modelURL = NSBundle.mainBundle().URLForResource("Weather", withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
    }()

    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        // Create the coordinator and store
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("SingleViewCoreData.sqlite")
        var failureReason = "There was an error creating or loading the application's saved data."
        do {
            try coordinator.addPersistentStoreWithType(self.storeType.storeTypeValue, configuration: nil, URL: url, options: nil)
        } catch {
            // Report any error we got.
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            dict[NSUnderlyingErrorKey] = error as NSError
            let wrappedError = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            // Replace this with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog("Unresolved error \(wrappedError), \(wrappedError.userInfo)")
            abort()
        }
        return coordinator
    }()

    lazy var mainQueueManagedObjectContext: NSManagedObjectContext = {
        let coordinator = self.persistentStoreCoordinator
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }()

    func createPrivateQueueManagedObjectContext() -> NSManagedObjectContext {
        let coordinator = self.persistentStoreCoordinator
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }

    // MARK: - Notifications

    @objc private func managedObjectContextDidSaveNotification(notification: NSNotification) {

        // Get context and ensure it's not a child context
        guard let notificationContext = notification.object as? NSManagedObjectContext where notificationContext.parentContext == nil else {
            return
        }

        // Merge processing changes into main context
        if notificationContext != mainQueueManagedObjectContext {
            mainQueueManagedObjectContext.performBlock {
                self.mainQueueManagedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
            }
        }

    }

}