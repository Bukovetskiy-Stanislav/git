
import Foundation

struct WDWeatherLocation {

    let cityName: String
    let countryCode: String


    static func londonGB() -> WDWeatherLocation {
        return WDWeatherLocation(cityName: "London", countryCode: "GB")
    }

}
