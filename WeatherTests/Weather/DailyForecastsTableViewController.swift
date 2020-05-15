

import UIKit
import CoreData
import SwiftyJSON
import AlamofireImage

class DailyForecastsTableViewController: UITableViewController {

    let dateFormatter = NSDateFormatter()
    var context: NSManagedObjectContext!

    // State
    let location = WDWeatherLocation.londonGB()
    var loading = true

    // Data
    var dailyForecasts: [WDWeatherDailyForecast]?

    // MARK: - UIView

    override func viewDidLoad() {

        // Start loading persisted data
        loadData()

        // Fetch latest data in background
        fetchNewData()

        // Title
        updateTitle()

        // Super
        super.viewDidLoad()

    }

    // MARK - Data

    private func fetchNewData() {

        // Fetch new data
        self.loading = true
        let weatherData = WDWeatherData(context: context)
        weatherData.fetchLatestWeatherData(location) {
            dispatch_async(dispatch_get_main_queue()) {

                // Update UI
                self.loading = false
                self.loadData() // Reload
                self.updateTitle()
                self.tableView.reloadData()

            }
        }

    }

    /// Get data from Core Data and display
    private func loadData() {

        // Fetch forecasts and group into days
        do {
            let forecasts = try Forecast.objectsInContext(self.context)
            if forecasts.count > 0 {
                self.dailyForecasts = WDWeatherDailyForecast.groupForecasts(forecasts)
            }
        } catch {
            log.error("Error getting forecasts")
        }

    }

    private func updateTitle() {
        self.navigationItem.title = loading ? "Updating..." : "Forecast for \(location.cityName), \(location.countryCode)"
    }

    // MARK: - UITableViewDataSource

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        // Section per day, or 1 for status cell
        return dailyForecasts?.count ?? 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let dailyForecasts = dailyForecasts {
            return dailyForecasts[section].forecasts.count
        } else {
            return 1 // Status cell
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if let dailyForecasts = dailyForecasts {
            // Forecast Cell
            let forecast = dailyForecasts[indexPath.section].forecasts[indexPath.row]
            let cell = tableView.dequeueReusableCellWithIdentifier("forecastCell", forIndexPath: indexPath)
            configureForecastCell(cell, forecast: forecast)
            return cell
        } else {
            // Status Cell
            let cell = tableView.dequeueReusableCellWithIdentifier("statusCell", forIndexPath: indexPath)
            cell.textLabel?.text = loading ? "Loading..." : "Could Not Load Forecast Data"
            return cell
        }
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let dailyForecasts = dailyForecasts {
            let dayIdentifier = dailyForecasts[section].dayIdentifier
            let date = dayIdentifier.date()!
            dateFormatter.dateStyle = .FullStyle
            dateFormatter.timeStyle = .NoStyle
            return dateFormatter.stringFromDate(date)
        }
        return nil
    }

    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if let _ = dailyForecasts {
            return 60
        } else {
            return 0
        }
    }

    // MARK: - Cells

    private func configureForecastCell(cell: UITableViewCell, forecast: Forecast) {

        // Load data
        let forecastDate = forecast.date!
        let data = JSON.parse(forecast.json!)

        // Weather info
        let weather = data["weather"].array?.first

        // Icon
        let placeholderIcon = UIImage(named: "WeatherIconPlaceholder.png")
        if let iconString = weather?["icon"].string {
            let iconURL = NSURL(string: "http://openweathermap.org/img/w/\(iconString).png")!
            cell.imageView?.af_setImageWithURL(iconURL, placeholderImage: placeholderIcon)
        } else {
            cell.imageView?.image = placeholderIcon
        }

        // Time
        dateFormatter.dateStyle = .NoStyle
        dateFormatter.timeStyle = .ShortStyle
        let timeString = dateFormatter.stringFromDate(forecastDate)

        // Info parts
        var infoParts: [String] = []

        // Weather description
        if let weatherDescription = weather?["description"].string?.capitalizedString {
            infoParts.append(weatherDescription)
        }

        // Temp
        if let temp = data["main"]["temp"].int {
            infoParts.append("🌡 \(temp)°")
        }

        // Wind speed
        if let wind = data["wind"]["speed"].int {
            infoParts.append("🌬 \(wind)m/s")
        }

        // Set labels
        cell.textLabel?.text = timeString
        cell.detailTextLabel?.text = infoParts.joinWithSeparator("   ")

    }

    // MARK: - Helpers

    private func indexPathsForDayForcasts(dailyForecast: WDWeatherDailyForecast, inSection section: Int) -> [NSIndexPath] {
        var indexPaths: [NSIndexPath] = []
        for i in 0 ..< dailyForecast.forecasts.count {
            indexPaths.append(NSIndexPath(forRow: i, inSection: section))
        }
        return indexPaths
    }

}
