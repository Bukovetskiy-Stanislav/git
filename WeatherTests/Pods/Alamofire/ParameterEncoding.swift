
import Foundation


public enum Method: String {
    case OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT
}


public enum ParameterEncoding {
    case URL
    case URLEncodedInURL
    case JSON
    case PropertyList(NSPropertyListFormat, NSPropertyListWriteOptions)
    case Custom((URLRequestConvertible, [String: AnyObject]?) -> (NSMutableURLRequest, NSError?))


    public func encode(
        URLRequest: URLRequestConvertible,
        parameters: [String: AnyObject]?)
        -> (NSMutableURLRequest, NSError?)
    {
        var mutableURLRequest = URLRequest.URLRequest

        guard let parameters = parameters else { return (mutableURLRequest, nil) }

        var encodingError: NSError? = nil

        switch self {
        case .URL, .URLEncodedInURL:
            func query(parameters: [String: AnyObject]) -> String {
                var components: [(String, String)] = []

                for key in parameters.keys.sort(<) {
                    let value = parameters[key]!
                    components += queryComponents(key, value)
                }

                return (components.map { "\($0)=\($1)" } as [String]).joinWithSeparator("&")
            }

            func encodesParametersInURL(method: Method) -> Bool {
                switch self {
                case .URLEncodedInURL:
                    return true
                default:
                    break
                }

                switch method {
                case .GET, .HEAD, .DELETE:
                    return true
                default:
                    return false
                }
            }

            if let method = Method(rawValue: mutableURLRequest.HTTPMethod) where encodesParametersInURL(method) {
                if let
                    URLComponents = NSURLComponents(URL: mutableURLRequest.URL!, resolvingAgainstBaseURL: false)
                    where !parameters.isEmpty
                {
                    let percentEncodedQuery = (URLComponents.percentEncodedQuery.map { $0 + "&" } ?? "") + query(parameters)
                    URLComponents.percentEncodedQuery = percentEncodedQuery
                    mutableURLRequest.URL = URLComponents.URL
                }
            } else {
                if mutableURLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableURLRequest.setValue(
                        "application/x-www-form-urlencoded; charset=utf-8",
                        forHTTPHeaderField: "Content-Type"
                    )
                }

                mutableURLRequest.HTTPBody = query(parameters).dataUsingEncoding(
                    NSUTF8StringEncoding,
                    allowLossyConversion: false
                )
            }
        case .JSON:
            do {
                let options = NSJSONWritingOptions()
                let data = try NSJSONSerialization.dataWithJSONObject(parameters, options: options)

                if mutableURLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableURLRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }

                mutableURLRequest.HTTPBody = data
            } catch {
                encodingError = error as NSError
            }
        case .PropertyList(let format, let options):
            do {
                let data = try NSPropertyListSerialization.dataWithPropertyList(
                    parameters,
                    format: format,
                    options: options
                )

                if mutableURLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableURLRequest.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
                }

                mutableURLRequest.HTTPBody = data
            } catch {
                encodingError = error as NSError
            }
        case .Custom(let closure):
            (mutableURLRequest, encodingError) = closure(mutableURLRequest, parameters)
        }

        return (mutableURLRequest, encodingError)
    }


    public func queryComponents(key: String, _ value: AnyObject) -> [(String, String)] {
        var components: [(String, String)] = []

        if let dictionary = value as? [String: AnyObject] {
            for (nestedKey, value) in dictionary {
                components += queryComponents("\(key)[\(nestedKey)]", value)
            }
        } else if let array = value as? [AnyObject] {
            for value in array {
                components += queryComponents("\(key)[]", value)
            }
        } else {
            components.append((escape(key), escape("\(value)")))
        }

        return components
    }

    public func escape(string: String) -> String {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="

        let allowedCharacterSet = NSCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        allowedCharacterSet.removeCharactersInString(generalDelimitersToEncode + subDelimitersToEncode)

        var escaped = ""


        if #available(iOS 8.3, OSX 10.10, *) {
            escaped = string.stringByAddingPercentEncodingWithAllowedCharacters(allowedCharacterSet) ?? string
        } else {
            let batchSize = 50
            var index = string.startIndex

            while index != string.endIndex {
                let startIndex = index
                let endIndex = index.advancedBy(batchSize, limit: string.endIndex)
                let range = startIndex..<endIndex

                let substring = string.substringWithRange(range)

                escaped += substring.stringByAddingPercentEncodingWithAllowedCharacters(allowedCharacterSet) ?? substring

                index = endIndex
            }
        }

        return escaped
    }
}
