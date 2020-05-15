

import Foundation
import CoreData

class Forecast: NSManagedObject {

}

extension Forecast {

    @NSManaged var date: NSDate?
    @NSManaged var json: String?

}

extension Forecast: FetchableManagedObject {

    static func entityName() -> String {
        return "Forecast"
    }

}
