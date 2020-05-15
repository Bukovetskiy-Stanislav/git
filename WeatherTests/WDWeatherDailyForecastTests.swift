
import XCTest
import CoreData
import Foundation
@testable import Weather

class WDWeatherDailyForecastTests: XCTestCase {

    let coreData = WDCoreData(storeType: .InMemory)

    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = coreData.createPrivateQueueManagedObjectContext()
    }

    func testGroupingForecasts() {

        // Perform in context's queue
        context.performBlockAndWait {

            // Given: Forecast objects
            let dateNow = NSDate()
            let dateTomorrow = NSDate().dateByAddingTimeInterval(60*60*24) // +1 day
            var forecasts: [Forecast] = []
            forecasts.append(self.createForecastObject(self.context, date: dateNow))
            forecasts.append(self.createForecastObject(self.context, date: dateNow))
            forecasts.append(self.createForecastObject(self.context, date: dateTomorrow))

            // When: We group them
            let dailyForecasts = WDWeatherDailyForecast.groupForecasts(forecasts)

            // Then: Check they are grouped correctly
            XCTAssertEqual(dailyForecasts.count, 2) // Split into 2 days
            XCTAssertEqual(dailyForecasts.first!.forecasts.count, 2)
            XCTAssertEqual(dailyForecasts.last!.forecasts.count, 1)

        }

    }

    /// Helper method to create forecast objects
    private func createForecastObject(context: NSManagedObjectContext, date: NSDate) -> Forecast {
        let forecast = Forecast.insertNewObject(context)
        forecast.date = date
        return forecast
    }

}
