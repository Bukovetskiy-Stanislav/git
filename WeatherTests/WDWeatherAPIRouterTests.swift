
import XCTest
@testable import Weather

class WDWeatherAPIRouterTests: XCTestCase {

    func testForecastRoute() {

        // Given...

        // Build forcast route
        let location = WDWeatherLocation.londonGB()
        let forecastRoute = WDWeatherAPIRouter.Forecast(location: location)

        // When...

        // Get the URL request
        let urlRequest = forecastRoute.URLRequest

        // Then...

        // Check the URL and parameters are correct
        let urlComponents = NSURLComponents(URL: urlRequest.URL!, resolvingAgainstBaseURL: false)!
        let queryItems = urlComponents.queryItems!

        // Check URL host and path
        XCTAssertEqual(urlComponents.URL!.host, "api.openweathermap.org")
        XCTAssertEqual(urlComponents.URL!.path, "/data/2.5/forecast")

        // Check location query string
        let queryQueryItem = queryItems[queryItems.indexOf({ $0.name == "q" })!]
        XCTAssertEqual(queryQueryItem.value, "\(location.cityName),\(location.countryCode)")

        // Check App ID query
        let appIDQueryItem = queryItems[queryItems.indexOf({ $0.name == "APPID" })!]
        XCTAssertEqual(appIDQueryItem.value, WDWeatherAPIRouter.appID)

        // Units
        let unitsQueryItem = queryItems[queryItems.indexOf({ $0.name == "units" })!]
        XCTAssertEqual(unitsQueryItem.value, WDWeatherAPIRouter.units.rawValue)

    }

}
