
import Foundation

struct DayIdentifier: Hashable, Equatable, Comparable {

    let year: Int
    let month: Int
    let day: Int

    /// Returns int in format yyyymmdd
    var rawValue: Int {
        return year * 10000 + month * 100 + day
    }

    // MARK: - NSDate

    static func fromComponents(components: NSDateComponents) -> DayIdentifier {
        return DayIdentifier(year: components.year, month: components.month, day: components.day)
    }

    func dateComponents() -> NSDateComponents {
        let c = NSDateComponents()
        c.year = year
        c.month = month
        c.day = day
        return c
    }

    func date() -> NSDate? {
        return NSCalendar.currentCalendar().dateFromComponents(dateComponents())
    }

    // MARK: - Hashable

    var hashValue: Int {
        return rawValue
    }

}

// MARK: - Equatable

func ==(lhs: DayIdentifier, rhs: DayIdentifier) -> Bool {
    return lhs.rawValue == rhs.rawValue
}

// MARK: - Comparable

func <(lhs: DayIdentifier, rhs: DayIdentifier) -> Bool {
    return lhs.rawValue < rhs.rawValue
}

func >(lhs: DayIdentifier, rhs: DayIdentifier) -> Bool {
    return lhs.rawValue > rhs.rawValue
}

func <=(lhs: DayIdentifier, rhs: DayIdentifier) -> Bool {
    return lhs.rawValue <= rhs.rawValue
}

func >=(lhs: DayIdentifier, rhs: DayIdentifier) -> Bool {
    return lhs.rawValue >= rhs.rawValue
}
