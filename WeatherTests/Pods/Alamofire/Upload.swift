
import Foundation

extension Manager {
    private enum Uploadable {
        case Data(NSURLRequest, NSData)
        case File(NSURLRequest, NSURL)
        case Stream(NSURLRequest, NSInputStream)
    }

    private func upload(uploadable: Uploadable) -> Request {
        var uploadTask: NSURLSessionUploadTask!
        var HTTPBodyStream: NSInputStream?

        switch uploadable {
        case .Data(let request, let data):
            dispatch_sync(queue) {
                uploadTask = self.session.uploadTaskWithRequest(request, fromData: data)
            }
        case .File(let request, let fileURL):
            dispatch_sync(queue) {
                uploadTask = self.session.uploadTaskWithRequest(request, fromFile: fileURL)
            }
        case .Stream(let request, let stream):
            dispatch_sync(queue) {
                uploadTask = self.session.uploadTaskWithStreamedRequest(request)
            }

            HTTPBodyStream = stream
        }

        let request = Request(session: session, task: uploadTask)

        if HTTPBodyStream != nil {
            request.delegate.taskNeedNewBodyStream = { _, _ in
                return HTTPBodyStream
            }
        }

        delegate[request.delegate.task] = request.delegate

        if startRequestsImmediately {
            request.resume()
        }

        return request
    }

    public func upload(URLRequest: URLRequestConvertible, file: NSURL) -> Request {
        return upload(.File(URLRequest.URLRequest, file))
    }
    public func upload(
        method: Method,
        _ URLString: URLStringConvertible,
        headers: [String: String]? = nil,
        file: NSURL)
        -> Request
    {
        let mutableURLRequest = URLRequest(method, URLString, headers: headers)
        return upload(mutableURLRequest, file: file)
    }
    public func upload(URLRequest: URLRequestConvertible, data: NSData) -> Request {
        return upload(.Data(URLRequest.URLRequest, data))
    }
    public func upload(
        method: Method,
        _ URLString: URLStringConvertible,
        headers: [String: String]? = nil,
        data: NSData)
        -> Request
    {
        let mutableURLRequest = URLRequest(method, URLString, headers: headers)

        return upload(mutableURLRequest, data: data)
    }
    public func upload(URLRequest: URLRequestConvertible, stream: NSInputStream) -> Request {
        return upload(.Stream(URLRequest.URLRequest, stream))
    }
    public func upload(
        method: Method,
        _ URLString: URLStringConvertible,
        headers: [String: String]? = nil,
        stream: NSInputStream)
        -> Request
    {
        let mutableURLRequest = URLRequest(method, URLString, headers: headers)

        return upload(mutableURLRequest, stream: stream)
    }
    public static let MultipartFormDataEncodingMemoryThreshold: UInt64 = 10 * 1024 * 1024
    public enum MultipartFormDataEncodingResult {
        case Success(request: Request, streamingFromDisk: Bool, streamFileURL: NSURL?)
        case Failure(ErrorType)
    }
    public func upload(
        method: Method,
        _ URLString: URLStringConvertible,
        headers: [String: String]? = nil,
        multipartFormData: MultipartFormData -> Void,
        encodingMemoryThreshold: UInt64 = Manager.MultipartFormDataEncodingMemoryThreshold,
        encodingCompletion: (MultipartFormDataEncodingResult -> Void)?)
    {
        let mutableURLRequest = URLRequest(method, URLString, headers: headers)

        return upload(
            mutableURLRequest,
            multipartFormData: multipartFormData,
            encodingMemoryThreshold: encodingMemoryThreshold,
            encodingCompletion: encodingCompletion
        )
    }
    public func upload(
        URLRequest: URLRequestConvertible,
        multipartFormData: MultipartFormData -> Void,
        encodingMemoryThreshold: UInt64 = Manager.MultipartFormDataEncodingMemoryThreshold,
        encodingCompletion: (MultipartFormDataEncodingResult -> Void)?)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            let formData = MultipartFormData()
            multipartFormData(formData)

            let URLRequestWithContentType = URLRequest.URLRequest
            URLRequestWithContentType.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")

            let isBackgroundSession = self.session.configuration.identifier != nil

            if formData.contentLength < encodingMemoryThreshold && !isBackgroundSession {
                do {
                    let data = try formData.encode()
                    let encodingResult = MultipartFormDataEncodingResult.Success(
                        request: self.upload(URLRequestWithContentType, data: data),
                        streamingFromDisk: false,
                        streamFileURL: nil
                    )

                    dispatch_async(dispatch_get_main_queue()) {
                        encodingCompletion?(encodingResult)
                    }
                } catch {
                    dispatch_async(dispatch_get_main_queue()) {
                        encodingCompletion?(.Failure(error as NSError))
                    }
                }
            } else {
                let fileManager = NSFileManager.defaultManager()
                let tempDirectoryURL = NSURL(fileURLWithPath: NSTemporaryDirectory())
                let directoryURL = tempDirectoryURL.URLByAppendingPathComponent("com.alamofire.manager/multipart.form.data")
                let fileName = NSUUID().UUIDString
                let fileURL = directoryURL.URLByAppendingPathComponent(fileName)

                do {
                    try fileManager.createDirectoryAtURL(directoryURL, withIntermediateDirectories: true, attributes: nil)
                    try formData.writeEncodedDataToDisk(fileURL)

                    dispatch_async(dispatch_get_main_queue()) {
                        let encodingResult = MultipartFormDataEncodingResult.Success(
                            request: self.upload(URLRequestWithContentType, file: fileURL),
                            streamingFromDisk: true,
                            streamFileURL: fileURL
                        )
                        encodingCompletion?(encodingResult)
                    }
                } catch {
                    dispatch_async(dispatch_get_main_queue()) {
                        encodingCompletion?(.Failure(error as NSError))
                    }
                }
            }
        }
    }
}
extension Request {
    class UploadTaskDelegate: DataTaskDelegate {
        var uploadTask: NSURLSessionUploadTask? { return task as? NSURLSessionUploadTask }
        var uploadProgress: ((Int64, Int64, Int64) -> Void)!
        var taskDidSendBodyData: ((NSURLSession, NSURLSessionTask, Int64, Int64, Int64) -> Void)?
        func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64)
        {
            if initialResponseTime == nil { initialResponseTime = CFAbsoluteTimeGetCurrent() }

            if let taskDidSendBodyData = taskDidSendBodyData {
                taskDidSendBodyData(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
            } else {
                progress.totalUnitCount = totalBytesExpectedToSend
                progress.completedUnitCount = totalBytesSent

                uploadProgress?(bytesSent, totalBytesSent, totalBytesExpectedToSend)
            }
        }
    }
}
