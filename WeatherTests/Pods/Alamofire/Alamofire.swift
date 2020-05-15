
import Foundation


public protocol URLStringConvertible {

    var URLString: String { get }
}

extension String: URLStringConvertible {
    public var URLString: String {
        return self
    }
}

extension NSURL: URLStringConvertible {
    public var URLString: String {
        return absoluteString
    }
}

extension NSURLComponents: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}

extension NSURLRequest: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}

public protocol URLRequestConvertible {
    /// The URL request.
    var URLRequest: NSMutableURLRequest { get }
}

extension NSURLRequest: URLRequestConvertible {
    public var URLRequest: NSMutableURLRequest {
        return self.mutableCopy() as! NSMutableURLRequest
    }
}

// MARK: - Convenience

func URLRequest(
    method: Method,
    _ URLString: URLStringConvertible,
    headers: [String: String]? = nil)
    -> NSMutableURLRequest
{
    let mutableURLRequest = NSMutableURLRequest(URL: NSURL(string: URLString.URLString)!)
    mutableURLRequest.HTTPMethod = method.rawValue

    if let headers = headers {
        for (headerField, headerValue) in headers {
            mutableURLRequest.setValue(headerValue, forHTTPHeaderField: headerField)
        }
    }

    return mutableURLRequest
}


public func request(
    method: Method,
    _ URLString: URLStringConvertible,
    parameters: [String: AnyObject]? = nil,
    encoding: ParameterEncoding = .URL,
    headers: [String: String]? = nil)
    -> Request
{
    return Manager.sharedInstance.request(
        method,
        URLString,
        parameters: parameters,
        encoding: encoding,
        headers: headers
    )
}


public func request(URLRequest: URLRequestConvertible) -> Request {
    return Manager.sharedInstance.request(URLRequest.URLRequest)
}


public func upload(
    method: Method,
    _ URLString: URLStringConvertible,
    headers: [String: String]? = nil,
    file: NSURL)
    -> Request
{
    return Manager.sharedInstance.upload(method, URLString, headers: headers, file: file)
}


public func upload(URLRequest: URLRequestConvertible, file: NSURL) -> Request {
    return Manager.sharedInstance.upload(URLRequest, file: file)
}

public func upload(
    method: Method,
    _ URLString: URLStringConvertible,
    headers: [String: String]? = nil,
    data: NSData)
    -> Request
{
    return Manager.sharedInstance.upload(method, URLString, headers: headers, data: data)
}


public func upload(URLRequest: URLRequestConvertible, data: NSData) -> Request {
    return Manager.sharedInstance.upload(URLRequest, data: data)
}


public func upload(
    method: Method,
    _ URLString: URLStringConvertible,
    headers: [String: String]? = nil,
    stream: NSInputStream)
    -> Request
{
    return Manager.sharedInstance.upload(method, URLString, headers: headers, stream: stream)
}


public func upload(URLRequest: URLRequestConvertible, stream: NSInputStream) -> Request {
    return Manager.sharedInstance.upload(URLRequest, stream: stream)
}


public func upload(
    method: Method,
    _ URLString: URLStringConvertible,
    headers: [String: String]? = nil,
    multipartFormData: MultipartFormData -> Void,
    encodingMemoryThreshold: UInt64 = Manager.MultipartFormDataEncodingMemoryThreshold,
    encodingCompletion: (Manager.MultipartFormDataEncodingResult -> Void)?)
{
    return Manager.sharedInstance.upload(
        method,
        URLString,
        headers: headers,
        multipartFormData: multipartFormData,
        encodingMemoryThreshold: encodingMemoryThreshold,
        encodingCompletion: encodingCompletion
    )
}


public func upload(
    URLRequest: URLRequestConvertible,
    multipartFormData: MultipartFormData -> Void,
    encodingMemoryThreshold: UInt64 = Manager.MultipartFormDataEncodingMemoryThreshold,
    encodingCompletion: (Manager.MultipartFormDataEncodingResult -> Void)?)
{
    return Manager.sharedInstance.upload(
        URLRequest,
        multipartFormData: multipartFormData,
        encodingMemoryThreshold: encodingMemoryThreshold,
        encodingCompletion: encodingCompletion
    )
}


public func download(
    method: Method,
    _ URLString: URLStringConvertible,
    parameters: [String: AnyObject]? = nil,
    encoding: ParameterEncoding = .URL,
    headers: [String: String]? = nil,
    destination: Request.DownloadFileDestination)
    -> Request
{
    return Manager.sharedInstance.download(
        method,
        URLString,
        parameters: parameters,
        encoding: encoding,
        headers: headers,
        destination: destination
    )
}


public func download(URLRequest: URLRequestConvertible, destination: Request.DownloadFileDestination) -> Request {
    return Manager.sharedInstance.download(URLRequest, destination: destination)
}


public func download(resumeData data: NSData, destination: Request.DownloadFileDestination) -> Request {
    return Manager.sharedInstance.download(data, destination: destination)
}
