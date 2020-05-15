

import XCTest
import CoreData
@testable import Weather

class WDWeatherDataTests: XCTestCase {

    let coreData = WDCoreData(storeType: .InMemory)

    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = coreData.createPrivateQueueManagedObjectContext()
    }

    func testFetchingLatestWeatherData() {

        let expectation = expectationWithDescription("Fetching data in the background")

        // Given: Weather data manager and a location
        let weatherData = WDWeatherData(context: context)
        let location = WDWeatherLocation.londonGB()

        // When: Fetch latest weather data
        weatherData.fetchLatestWeatherData(location) {

            // Then: Check context for imported objects
            self.context.performBlock {

                // Check managed objects
                XCTAssertTrue(Forecast.objectCountInContext(self.context) > 0, "Forecast objects should exist")

                // Finish
                expectation.fulfill()

            }

        }

        // Wait for fetch
        waitForExpectationsWithTimeout(10) { (error) in
            print("Failed waiting for data fetch with error: \(error)")
        }

    }

}
