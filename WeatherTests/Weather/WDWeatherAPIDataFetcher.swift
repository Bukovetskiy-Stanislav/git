
import Foundation
import Alamofire
import SwiftyJSON

class WDWeatherAPIDataFetcher {

    let router: WDWeatherAPIRouter

    init(router: WDWeatherAPIRouter) {
        self.router = router
    }

    /// Fetch JSON data for a given route
    func fetchData(completion: (data: JSON?, error: NSError?) -> Void) {
        Alamofire.request(router)
            .validate()
            .responseJSON { response in
                switch response.result {
                case .Success(let value):
                    completion(data: JSON(value), error: nil)
                case .Failure(let error):
                    completion(data: nil, error: error)
                }
            }
    }

}