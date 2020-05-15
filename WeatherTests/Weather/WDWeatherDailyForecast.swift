

import Foundation

struct WDWeatherDailyForecast {

    let dayIdentifier: DayIdentifier
    let forecasts: [Forecast]

    /// Returns an array of daily forecasts in ascending order
    /// This must be called on the correct context's queue
    static func groupForecasts(forecasts: [Forecast]) -> [WDWeatherDailyForecast] {

        // Ensure we have forecasts
        guard !forecasts.isEmpty else {
            return []
        }

        // Group all forecasts into days
        let calendar = NSCalendar.currentCalendar()
        var grouped: [DayIdentifier: [Forecast]] = [:]
        for forecast in forecasts {
            guard let forecastDate = forecast.date else {
                continue
            }
            // Get day identifier
            let comps = calendar.components([.Year, .Month, .Day], fromDate: forecastDate)
            let dayIdentifier = DayIdentifier.fromComponents(comps)
            // Add to grouped
            var forecasts = grouped[dayIdentifier] ?? [Forecast]()
            forecasts.append(forecast)
            grouped[dayIdentifier] = forecasts
        }

        // Create daily forecast objects
        var dailyForecasts: [WDWeatherDailyForecast] = []
        for (dayIdentifier, forecasts) in grouped {
            let sortedForecasts = forecasts.sort { $0.date! < $1.date! }
            let dailyForecast = WDWeatherDailyForecast(dayIdentifier: dayIdentifier, forecasts: sortedForecasts)
            dailyForecasts.append(dailyForecast)
        }

        // Return sorted daily forecasts
        return dailyForecasts.sort { $0.dayIdentifier < $1.dayIdentifier }

    }

}
