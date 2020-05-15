
import Foundation
import Alamofire

/// Router that maps an endpoint with parameters into an NSURLRequest
enum WDWeatherAPIRouter: URLRequestConvertible {

    enum Units: String {
        case Metric = "metric"
        case Imperial = "imperial"
    }

    static let baseURLString = "http://api.openweathermap.org/data/2.5"
    static let appID = "26cb19a76230f03bd78f436435324fec"
    static let units: Units = .Metric

    // MARK: - Endpoints

    case Forecast(location: WDWeatherLocation)

    // MARK: - URLRequestConvertible

    var URLRequest: NSMutableURLRequest {

        // Get path and parameters
        let result: (path: String, parameters: [String: AnyObject]) = {
            switch self {
            case .Forecast(let location):
                return ("/forecast", ["q": "\(location.cityName),\(location.countryCode)"])
            }
        }()

        // Build URL and request
        let URL = NSURL(string: WDWeatherAPIRouter.baseURLString)!
        let URLRequest = NSURLRequest(URL: URL.URLByAppendingPathComponent(result.path))

        // Default parameters for all requests
        let defaultParameters = [
            "APPID": WDWeatherAPIRouter.appID,
            "units": WDWeatherAPIRouter.units.rawValue,
        ]

        // Return URL request with all encoded parameters
        let encoding = Alamofire.ParameterEncoding.URL
        let finalParameters = defaultParameters + result.parameters
        return encoding.encode(URLRequest, parameters: finalParameters).0

    }

}
