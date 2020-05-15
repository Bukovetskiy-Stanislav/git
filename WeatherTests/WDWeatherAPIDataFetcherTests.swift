

import XCTest
@testable import Weather

class WDWeatherAPIDataFetcherTests: XCTestCase {

    func testFetchingForecastData() {

        // Given
        let location = WDWeatherLocation.londonGB()
        let forecastRouter = WDWeatherAPIRouter.Forecast(location: location)
        let forecastDataFetcher = WDWeatherAPIDataFetcher(router: forecastRouter)

        // When
        let expectation = expectationWithDescription("Fetching data")
        forecastDataFetcher.fetchData { (data, error) in

            // Then...
            guard let data = data where error == nil else {
                XCTFail("Failure getting data with error: \(error)")
                return
            }

            // Check response contains the correct country
            XCTAssertEqual(data["city"]["name"].string, location.cityName)
            XCTAssertEqual(data["city"]["country"].string, location.countryCode)

            // Check items are returned
            XCTAssertFalse(data["list"].array!.isEmpty, "List does not contain any items")

            // Completed
            expectation.fulfill()

        }

        // Wait for fetch
        waitForExpectationsWithTimeout(10) { (error) in
            print("Failed waiting for data fetch with error: \(error)")
        }

    }

}
