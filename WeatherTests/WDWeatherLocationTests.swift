

import XCTest
@testable import Weather

class WDWeatherLocationTests: XCTestCase {

    func testLondonForecastRoute() {

        // Ensure that the london weather location values are correct
        let location = WDWeatherLocation.londonGB()
        XCTAssertEqual(location.cityName, "London")
        XCTAssertEqual(location.countryCode, "GB")

    }

}
