

import Foundation
import CoreData
import SwiftyJSON

class WDWeatherForecastDataImportOperation: ConcurrentOperation {

    let dataFetcher: WDWeatherAPIDataFetcher
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext, location: WDWeatherLocation) {

        // Configure
        self.context = context

        // Setup router and data fetcher
        let router = WDWeatherAPIRouter.Forecast(location: location)
        dataFetcher = WDWeatherAPIDataFetcher(router: router)

        // Super
        super.init()

        // The user will be waiting for this data
        self.queuePriority = .High
        self.qualityOfService = .UserInitiated

    }

    override func start() {

        // Begin executing
        state == .Executing

        // Fetch data
        dataFetcher.fetchData { (data, error) in

            // Check response
            guard let data = data where error == nil else {
                log.error("Error fetching data for request \(self.dataFetcher.router.URLRequest.URL) error: \(error)")
                self.state = .Finished
                return
            }

            // Import data in context's queue and finish
            self.context.performBlock {
                self.overwriteForecastObjects(data)
                self.state = .Finished
            }

        }

    }

    /// Delete all existing forecast objects and saves new ones
    /// Called on the context's queue
    private func overwriteForecastObjects(data: JSON) {

        // Get list of items
        guard let list = data["list"].array where !list.isEmpty else {
            log.warning("No list items returned for request \(self.dataFetcher.router.URLRequest.URL)")
            return
        }

        // Delete all previous forecasts
        do {
            let allForecastObjects = try Forecast.objectsInContext(context)
            _ = allForecastObjects.map { context.deleteObject($0) }
        } catch {
            log.error("Error getting existing forecast objects: \(error)")
        }

        // Import items
        for item in list {

            // Get required data
            guard let dateTimestamp = item["dt"].double else {
                continue
            }

            // Create new forecast object
            let forecast = Forecast.insertNewObject(context)
            forecast.date = NSDate(timeIntervalSince1970: dateTimestamp)
            forecast.json = item.rawString()

        }

        // Save changes
        do {
            try context.save()
        } catch {
            log.error("Failed to save context: \(error)")
        }

    }

}