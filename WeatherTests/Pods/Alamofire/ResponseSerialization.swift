

import Foundation

public protocol ResponseSerializerType {
    associatedtype SerializedObject

    associatedtype ErrorObject: ErrorType


    var serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> Result<SerializedObject, ErrorObject> { get }
}


public struct ResponseSerializer<Value, Error: ErrorType>: ResponseSerializerType {
    public typealias SerializedObject = Value

    public typealias ErrorObject = Error


    public var serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> Result<Value, Error>

    public init(serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> Result<Value, Error>) {
        self.serializeResponse = serializeResponse
    }
}


extension Request {

    public func response(
        queue queue: dispatch_queue_t? = nil,
        completionHandler: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> Void)
        -> Self
    {
        delegate.queue.addOperationWithBlock {
            dispatch_async(queue ?? dispatch_get_main_queue()) {
                completionHandler(self.request, self.response, self.delegate.data, self.delegate.error)
            }
        }

        return self
    }

    public func response<T: ResponseSerializerType>(
        queue queue: dispatch_queue_t? = nil,
        responseSerializer: T,
        completionHandler: Response<T.SerializedObject, T.ErrorObject> -> Void)
        -> Self
    {
        delegate.queue.addOperationWithBlock {
            let result = responseSerializer.serializeResponse(
                self.request,
                self.response,
                self.delegate.data,
                self.delegate.error
            )

            let requestCompletedTime = self.endTime ?? CFAbsoluteTimeGetCurrent()
            let initialResponseTime = self.delegate.initialResponseTime ?? requestCompletedTime

            let timeline = Timeline(
                requestStartTime: self.startTime ?? CFAbsoluteTimeGetCurrent(),
                initialResponseTime: initialResponseTime,
                requestCompletedTime: requestCompletedTime,
                serializationCompletedTime: CFAbsoluteTimeGetCurrent()
            )

            let response = Response<T.SerializedObject, T.ErrorObject>(
                request: self.request,
                response: self.response,
                data: self.delegate.data,
                result: result,
                timeline: timeline
            )

            dispatch_async(queue ?? dispatch_get_main_queue()) { completionHandler(response) }
        }

        return self
    }
}


extension Request {

    public static func dataResponseSerializer() -> ResponseSerializer<NSData, NSError> {
        return ResponseSerializer { _, response, data, error in
            guard error == nil else { return .Failure(error!) }

            if let response = response where response.statusCode == 204 { return .Success(NSData()) }

            guard let validData = data else {
                let failureReason = "Data could not be serialized. Input data was nil."
                let error = Error.error(code: .DataSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }

            return .Success(validData)
        }
    }


    public func responseData(
        queue queue: dispatch_queue_t? = nil,
        completionHandler: Response<NSData, NSError> -> Void)
        -> Self
    {
        return response(queue: queue, responseSerializer: Request.dataResponseSerializer(), completionHandler: completionHandler)
    }
}


extension Request {

    public static func stringResponseSerializer(
        encoding encoding: NSStringEncoding? = nil)
        -> ResponseSerializer<String, NSError>
    {
        return ResponseSerializer { _, response, data, error in
            guard error == nil else { return .Failure(error!) }

            if let response = response where response.statusCode == 204 { return .Success("") }

            guard let validData = data else {
                let failureReason = "String could not be serialized. Input data was nil."
                let error = Error.error(code: .StringSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }
            
            var convertedEncoding = encoding
            
            if let encodingName = response?.textEncodingName where convertedEncoding == nil {
                convertedEncoding = CFStringConvertEncodingToNSStringEncoding(
                    CFStringConvertIANACharSetNameToEncoding(encodingName)
                )
            }

            let actualEncoding = convertedEncoding ?? NSISOLatin1StringEncoding

            if let string = String(data: validData, encoding: actualEncoding) {
                return .Success(string)
            } else {
                let failureReason = "String could not be serialized with encoding: \(actualEncoding)"
                let error = Error.error(code: .StringSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }
        }
    }

    public func responseString(
        queue queue: dispatch_queue_t? = nil,
        encoding: NSStringEncoding? = nil,
        completionHandler: Response<String, NSError> -> Void)
        -> Self
    {
        return response(
            queue: queue,
            responseSerializer: Request.stringResponseSerializer(encoding: encoding),
            completionHandler: completionHandler
        )
    }
}


extension Request {

    public static func JSONResponseSerializer(
        options options: NSJSONReadingOptions = .AllowFragments)
        -> ResponseSerializer<AnyObject, NSError>
    {
        return ResponseSerializer { _, response, data, error in
            guard error == nil else { return .Failure(error!) }

            if let response = response where response.statusCode == 204 { return .Success(NSNull()) }

            guard let validData = data where validData.length > 0 else {
                let failureReason = "JSON could not be serialized. Input data was nil or zero length."
                let error = Error.error(code: .JSONSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }

            do {
                let JSON = try NSJSONSerialization.JSONObjectWithData(validData, options: options)
                return .Success(JSON)
            } catch {
                return .Failure(error as NSError)
            }
        }
    }

    public func responseJSON(
        queue queue: dispatch_queue_t? = nil,
        options: NSJSONReadingOptions = .AllowFragments,
        completionHandler: Response<AnyObject, NSError> -> Void)
        -> Self
    {
        return response(
            queue: queue,
            responseSerializer: Request.JSONResponseSerializer(options: options),
            completionHandler: completionHandler
        )
    }
}

extension Request {

    public static func propertyListResponseSerializer(
        options options: NSPropertyListReadOptions = NSPropertyListReadOptions())
        -> ResponseSerializer<AnyObject, NSError>
    {
        return ResponseSerializer { _, response, data, error in
            guard error == nil else { return .Failure(error!) }

            if let response = response where response.statusCode == 204 { return .Success(NSNull()) }

            guard let validData = data where validData.length > 0 else {
                let failureReason = "Property list could not be serialized. Input data was nil or zero length."
                let error = Error.error(code: .PropertyListSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }

            do {
                let plist = try NSPropertyListSerialization.propertyListWithData(validData, options: options, format: nil)
                return .Success(plist)
            } catch {
                return .Failure(error as NSError)
            }
        }
    }

    public func responsePropertyList(
        queue queue: dispatch_queue_t? = nil,
        options: NSPropertyListReadOptions = NSPropertyListReadOptions(),
        completionHandler: Response<AnyObject, NSError> -> Void)
        -> Self
    {
        return response(
            queue: queue,
            responseSerializer: Request.propertyListResponseSerializer(options: options),
            completionHandler: completionHandler
        )
    }
}
