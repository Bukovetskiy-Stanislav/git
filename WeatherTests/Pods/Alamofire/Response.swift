
import Foundation

public struct Response<Value, Error: ErrorType> {
    public let request: NSURLRequest?
    public let response: NSHTTPURLResponse?
    public let data: NSData?
    public let result: Result<Value, Error>
    public let timeline: Timeline

    public init(
        request: NSURLRequest?,
        response: NSHTTPURLResponse?,
        data: NSData?,
        result: Result<Value, Error>,
        timeline: Timeline = Timeline())
    {
        self.request = request
        self.response = response
        self.data = data
        self.result = result
        self.timeline = timeline
    }
}


extension Response: CustomStringConvertible {
    public var description: String {
        return result.debugDescription
    }
}

extension Response: CustomDebugStringConvertible {
    public var debugDescription: String {
        var output: [String] = []

        output.append(request != nil ? "[Request]: \(request!)" : "[Request]: nil")
        output.append(response != nil ? "[Response]: \(response!)" : "[Response]: nil")
        output.append("[Data]: \(data?.length ?? 0) bytes")
        output.append("[Result]: \(result.debugDescription)")
        output.append("[Timeline]: \(timeline.debugDescription)")

        return output.joinWithSeparator("\n")
    }
}
