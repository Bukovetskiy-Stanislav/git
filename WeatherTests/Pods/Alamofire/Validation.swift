

import Foundation

extension Request {
    public enum ValidationResult {
        case Success
        case Failure(NSError)
    }
    public typealias Validation = (NSURLRequest?, NSHTTPURLResponse) -> ValidationResult
    public func validate(validation: Validation) -> Self {
        delegate.queue.addOperationWithBlock {
            if let
                response = self.response where self.delegate.error == nil,
                case let .Failure(error) = validation(self.request, response)
            {
                self.delegate.error = error
            }
        }

        return self
    }
    public func validate<S: SequenceType where S.Generator.Element == Int>(statusCode acceptableStatusCode: S) -> Self {
        return validate { _, response in
            if acceptableStatusCode.contains(response.statusCode) {
                return .Success
            } else {
                let failureReason = "Response status code was unacceptable: \(response.statusCode)"

                let error = NSError(
                    domain: Error.Domain,
                    code: Error.Code.StatusCodeValidationFailed.rawValue,
                    userInfo: [
                        NSLocalizedFailureReasonErrorKey: failureReason,
                        Error.UserInfoKeys.StatusCode: response.statusCode
                    ]
                )

                return .Failure(error)
            }
        }
    }
    private struct MIMEType {
        let type: String
        let subtype: String

        init?(_ string: String) {
            let components: [String] = {
                let stripped = string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
                let split = stripped.substringToIndex(stripped.rangeOfString(";")?.startIndex ?? stripped.endIndex)
                return split.componentsSeparatedByString("/")
            }()

            if let
                type = components.first,
                subtype = components.last
            {
                self.type = type
                self.subtype = subtype
            } else {
                return nil
            }
        }

        func matches(MIME: MIMEType) -> Bool {
            switch (type, subtype) {
            case (MIME.type, MIME.subtype), (MIME.type, "*"), ("*", MIME.subtype), ("*", "*"):
                return true
            default:
                return false
            }
        }
    }
    public func validate<S : SequenceType where S.Generator.Element == String>(contentType acceptableContentTypes: S) -> Self {
        return validate { _, response in
            guard let validData = self.delegate.data where validData.length > 0 else { return .Success }

            if let
                responseContentType = response.MIMEType,
                responseMIMEType = MIMEType(responseContentType)
            {
                for contentType in acceptableContentTypes {
                    if let acceptableMIMEType = MIMEType(contentType) where acceptableMIMEType.matches(responseMIMEType) {
                        return .Success
                    }
                }
            } else {
                for contentType in acceptableContentTypes {
                    if let MIMEType = MIMEType(contentType) where MIMEType.type == "*" && MIMEType.subtype == "*" {
                        return .Success
                    }
                }
            }

            let contentType: String
            let failureReason: String

            if let responseContentType = response.MIMEType {
                contentType = responseContentType

                failureReason = (
                    "Response content type \"\(responseContentType)\" does not match any acceptable " +
                    "content types: \(acceptableContentTypes)"
                )
            } else {
                contentType = ""
                failureReason = "Response content type was missing and acceptable content type does not match \"*/*\""
            }

            let error = NSError(
                domain: Error.Domain,
                code: Error.Code.ContentTypeValidationFailed.rawValue,
                userInfo: [
                    NSLocalizedFailureReasonErrorKey: failureReason,
                    Error.UserInfoKeys.ContentType: contentType
                ]
            )

            return .Failure(error)
        }
    }
    public func validate() -> Self {
        let acceptableStatusCodes: Range<Int> = 200..<300
        let acceptableContentTypes: [String] = {
            if let accept = request?.valueForHTTPHeaderField("Accept") {
                return accept.componentsSeparatedByString(",")
            }

            return ["*/*"]
        }()

        return validate(statusCode: acceptableStatusCodes).validate(contentType: acceptableContentTypes)
    }
}
