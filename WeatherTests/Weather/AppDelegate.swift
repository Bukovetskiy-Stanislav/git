

import UIKit
import XCGLogger

// Get default logger
let log = XCGLogger.defaultInstance()

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    let coreData = WDCoreData()

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {

        // Configure logging
        log.setup(.Debug, showThreadName: true, showLogLevel: true, showFileNames: true, showLineNumbers: true, fileLogLevel: .Debug)

        // Pass main context to first VC
        let navigationController = window!.rootViewController as! UINavigationController
        let dailyForecastsTVC = navigationController.viewControllers.first as! DailyForecastsTableViewController
        dailyForecastsTVC.context = coreData.mainQueueManagedObjectContext

        // Continue
        return true
    }

}

