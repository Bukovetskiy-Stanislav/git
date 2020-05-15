
import Foundation

public struct Error {
    public static let Domain = "com.alamofire.error"

    public enum Code: Int {
        case InputStreamReadFailed           = -6000
        case OutputStreamWriteFailed         = -6001
        case ContentTypeValidationFailed     = -6002
        case StatusCodeValidationFailed      = -6003
        case DataSerializationFailed         = -6004
        case StringSerializationFailed       = -6005
        case JSONSerializationFailed         = -6006
        case PropertyListSerializationFailed = -6007
    }

    public struct UserInfoKeys {
        public static let ContentType = "ContentType"

        public static let StatusCode = "StatusCode"
    }


    @available(*, deprecated=3.4.0)
    public static func errorWithCode(code: Code, failureReason: String) -> NSError {
        return errorWithCode(code.rawValue, failureReason: failureReason)
    }

    @available(*, deprecated=3.4.0)
    public static func errorWithCode(code: Int, failureReason: String) -> NSError {
        let userInfo = [NSLocalizedFailureReasonErrorKey: failureReason]
        return NSError(domain: Domain, code: code, userInfo: userInfo)
    }

    static func error(domain domain: String = Error.Domain, code: Code, failureReason: String) -> NSError {
        return error(domain: domain, code: code.rawValue, failureReason: failureReason)
    }

    static func error(domain domain: String = Error.Domain, code: Int, failureReason: String) -> NSError {
        let userInfo = [NSLocalizedFailureReasonErrorKey: failureReason]
        return NSError(domain: domain, code: code, userInfo: userInfo)
    }
}
