
import Foundation
import XCTest
@testable import Weather

class WDWeatherForecastDataImportOperationTest: XCTestCase {

    let queue = NSOperationQueue()
    let coreData = WDCoreData(storeType: .InMemory)

    func testDataImportOperation() {

        // Create expectation
        let expectation = expectationWithDescription("Fetching data")

        // Given
        let context = coreData.createPrivateQueueManagedObjectContext()
        let location = WDWeatherLocation.londonGB()
        let forecastImportOperation = WDWeatherForecastDataImportOperation(context: context, location: location)
        forecastImportOperation.completionBlock = {

            // Then: Check context for imported objects
            context.performBlock {

                // Check managed objects
                XCTAssertTrue(Forecast.objectCountInContext(context) > 0, "Forecast objects should exist")

                // Finish
                expectation.fulfill()

            }

        }

        // When: Operation executes
        queue.addOperation(forecastImportOperation)

        // Wait for operation
        waitForExpectationsWithTimeout(30) { (error) in
            print("Failed waiting for data fetch with error: \(error)")
        }

    }

}
