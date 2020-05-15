
import Foundation


public class Manager {

    public static let sharedInstance: Manager = {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPAdditionalHeaders = Manager.defaultHTTPHeaders

        return Manager(configuration: configuration)
    }()

    public static let defaultHTTPHeaders: [String: String] = {
        let acceptEncoding: String = "gzip;q=1.0, compress;q=0.5"

        let acceptLanguage = NSLocale.preferredLanguages().prefix(6).enumerate().map { index, languageCode in
            let quality = 1.0 - (Double(index) * 0.1)
            return "\(languageCode);q=\(quality)"
        }.joinWithSeparator(", ")

        let userAgent: String = {
            if let info = NSBundle.mainBundle().infoDictionary {
                let executable = info[kCFBundleExecutableKey as String] as? String ?? "Unknown"
                let bundle = info[kCFBundleIdentifierKey as String] as? String ?? "Unknown"
                let version = info[kCFBundleVersionKey as String] as? String ?? "Unknown"

                let osNameVersion: String = {
                    let versionString: String

                    if #available(OSX 10.10, *) {
                        let version = NSProcessInfo.processInfo().operatingSystemVersion
                        versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
                    } else {
                        versionString = "10.9"
                    }

                    let osName: String = {
                        #if os(iOS)
                            return "iOS"
                        #elseif os(watchOS)
                            return "watchOS"
                        #elseif os(tvOS)
                            return "tvOS"
                        #elseif os(OSX)
                            return "OS X"
                        #elseif os(Linux)
                            return "Linux"
                        #else
                            return "Unknown"
                        #endif
                    }()

                    return "\(osName) \(versionString)"
                }()

                return "\(executable)/\(bundle) (\(version); \(osNameVersion))"
            }

            return "Alamofire"
        }()

        return [
            "Accept-Encoding": acceptEncoding,
            "Accept-Language": acceptLanguage,
            "User-Agent": userAgent
        ]
    }()

    let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)

    public let session: NSURLSession

    public let delegate: SessionDelegate

    public var startRequestsImmediately: Bool = true


    public var backgroundCompletionHandler: (() -> Void)?


    public init(
        configuration: NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration(),
        delegate: SessionDelegate = SessionDelegate(),
        serverTrustPolicyManager: ServerTrustPolicyManager? = nil)
    {
        self.delegate = delegate
        self.session = NSURLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        commonInit(serverTrustPolicyManager: serverTrustPolicyManager)
    }


    public init?(
        session: NSURLSession,
        delegate: SessionDelegate,
        serverTrustPolicyManager: ServerTrustPolicyManager? = nil)
    {
        guard delegate === session.delegate else { return nil }

        self.delegate = delegate
        self.session = session

        commonInit(serverTrustPolicyManager: serverTrustPolicyManager)
    }

    private func commonInit(serverTrustPolicyManager serverTrustPolicyManager: ServerTrustPolicyManager?) {
        session.serverTrustPolicyManager = serverTrustPolicyManager

        delegate.sessionDidFinishEventsForBackgroundURLSession = { [weak self] session in
            guard let strongSelf = self else { return }
            dispatch_async(dispatch_get_main_queue()) { strongSelf.backgroundCompletionHandler?() }
        }
    }

    deinit {
        session.invalidateAndCancel()
    }


    public func request(
        method: Method,
        _ URLString: URLStringConvertible,
        parameters: [String: AnyObject]? = nil,
        encoding: ParameterEncoding = .URL,
        headers: [String: String]? = nil)
        -> Request
    {
        let mutableURLRequest = URLRequest(method, URLString, headers: headers)
        let encodedURLRequest = encoding.encode(mutableURLRequest, parameters: parameters).0
        return request(encodedURLRequest)
    }

    public func request(URLRequest: URLRequestConvertible) -> Request {
        var dataTask: NSURLSessionDataTask!
        dispatch_sync(queue) { dataTask = self.session.dataTaskWithRequest(URLRequest.URLRequest) }

        let request = Request(session: session, task: dataTask)
        delegate[request.delegate.task] = request.delegate

        if startRequestsImmediately {
            request.resume()
        }

        return request
    }

    public class SessionDelegate: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate {
        private var subdelegates: [Int: Request.TaskDelegate] = [:]
        private let subdelegateQueue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)

        /// Access the task delegate for the specified task in a thread-safe manner.
        public subscript(task: NSURLSessionTask) -> Request.TaskDelegate? {
            get {
                var subdelegate: Request.TaskDelegate?
                dispatch_sync(subdelegateQueue) { subdelegate = self.subdelegates[task.taskIdentifier] }

                return subdelegate
            }
            set {
                dispatch_barrier_async(subdelegateQueue) { self.subdelegates[task.taskIdentifier] = newValue }
            }
        }


        public override init() {
            super.init()
        }


        public var sessionDidBecomeInvalidWithError: ((NSURLSession, NSError?) -> Void)?

        public var sessionDidReceiveChallenge: ((NSURLSession, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential?))?

        public var sessionDidReceiveChallengeWithCompletion: ((NSURLSession, NSURLAuthenticationChallenge, (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) -> Void)?

        public var sessionDidFinishEventsForBackgroundURLSession: ((NSURLSession) -> Void)?


        public func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
            sessionDidBecomeInvalidWithError?(session, error)
        }


        public func URLSession(
            session: NSURLSession,
            didReceiveChallenge challenge: NSURLAuthenticationChallenge,
            completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void))
        {
            guard sessionDidReceiveChallengeWithCompletion == nil else {
                sessionDidReceiveChallengeWithCompletion?(session, challenge, completionHandler)
                return
            }

            var disposition: NSURLSessionAuthChallengeDisposition = .PerformDefaultHandling
            var credential: NSURLCredential?

            if let sessionDidReceiveChallenge = sessionDidReceiveChallenge {
                (disposition, credential) = sessionDidReceiveChallenge(session, challenge)
            } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                let host = challenge.protectionSpace.host

                if let
                    serverTrustPolicy = session.serverTrustPolicyManager?.serverTrustPolicyForHost(host),
                    serverTrust = challenge.protectionSpace.serverTrust
                {
                    if serverTrustPolicy.evaluateServerTrust(serverTrust, isValidForHost: host) {
                        disposition = .UseCredential
                        credential = NSURLCredential(forTrust: serverTrust)
                    } else {
                        disposition = .CancelAuthenticationChallenge
                    }
                }
            }

            completionHandler(disposition, credential)
        }

        public func URLSessionDidFinishEventsForBackgroundURLSession(session: NSURLSession) {
            sessionDidFinishEventsForBackgroundURLSession?(session)
        }

        public var taskWillPerformHTTPRedirection: ((NSURLSession, NSURLSessionTask, NSHTTPURLResponse, NSURLRequest) -> NSURLRequest?)?

        public var taskWillPerformHTTPRedirectionWithCompletion: ((NSURLSession, NSURLSessionTask, NSHTTPURLResponse, NSURLRequest, NSURLRequest? -> Void) -> Void)?

        public var taskDidReceiveChallenge: ((NSURLSession, NSURLSessionTask, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential?))?

        public var taskDidReceiveChallengeWithCompletion: ((NSURLSession, NSURLSessionTask, NSURLAuthenticationChallenge, (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) -> Void)?

        public var taskNeedNewBodyStream: ((NSURLSession, NSURLSessionTask) -> NSInputStream?)?

        public var taskNeedNewBodyStreamWithCompletion: ((NSURLSession, NSURLSessionTask, NSInputStream? -> Void) -> Void)?

        public var taskDidSendBodyData: ((NSURLSession, NSURLSessionTask, Int64, Int64, Int64) -> Void)?

        public var taskDidComplete: ((NSURLSession, NSURLSessionTask, NSError?) -> Void)?



        public func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            willPerformHTTPRedirection response: NSHTTPURLResponse,
            newRequest request: NSURLRequest,
            completionHandler: NSURLRequest? -> Void)
        {
            guard taskWillPerformHTTPRedirectionWithCompletion == nil else {
                taskWillPerformHTTPRedirectionWithCompletion?(session, task, response, request, completionHandler)
                return
            }

            var redirectRequest: NSURLRequest? = request

            if let taskWillPerformHTTPRedirection = taskWillPerformHTTPRedirection {
                redirectRequest = taskWillPerformHTTPRedirection(session, task, response, request)
            }

            completionHandler(redirectRequest)
        }

        public func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            didReceiveChallenge challenge: NSURLAuthenticationChallenge,
            completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void)
        {
            guard taskDidReceiveChallengeWithCompletion == nil else {
                taskDidReceiveChallengeWithCompletion?(session, task, challenge, completionHandler)
                return
            }

            if let taskDidReceiveChallenge = taskDidReceiveChallenge {
                let result = taskDidReceiveChallenge(session, task, challenge)
                completionHandler(result.0, result.1)
            } else if let delegate = self[task] {
                delegate.URLSession(
                    session,
                    task: task,
                    didReceiveChallenge: challenge,
                    completionHandler: completionHandler
                )
            } else {
                URLSession(session, didReceiveChallenge: challenge, completionHandler: completionHandler)
            }
        }


        public func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            needNewBodyStream completionHandler: NSInputStream? -> Void)
        {
            guard taskNeedNewBodyStreamWithCompletion == nil else {
                taskNeedNewBodyStreamWithCompletion?(session, task, completionHandler)
                return
            }

            if let taskNeedNewBodyStream = taskNeedNewBodyStream {
                completionHandler(taskNeedNewBodyStream(session, task))
            } else if let delegate = self[task] {
                delegate.URLSession(session, task: task, needNewBodyStream: completionHandler)
            }
        }


        public func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64)
        {
            if let taskDidSendBodyData = taskDidSendBodyData {
                taskDidSendBodyData(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
            } else if let delegate = self[task] as? Request.UploadTaskDelegate {
                delegate.URLSession(
                    session,
                    task: task,
                    didSendBodyData: bytesSent,
                    totalBytesSent: totalBytesSent,
                    totalBytesExpectedToSend: totalBytesExpectedToSend
                )
            }
        }


        public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
            if let taskDidComplete = taskDidComplete {
                taskDidComplete(session, task, error)
            } else if let delegate = self[task] {
                delegate.URLSession(session, task: task, didCompleteWithError: error)
            }

            NSNotificationCenter.defaultCenter().postNotificationName(Notifications.Task.DidComplete, object: task)

            self[task] = nil
        }


        public var dataTaskDidReceiveResponse: ((NSURLSession, NSURLSessionDataTask, NSURLResponse) -> NSURLSessionResponseDisposition)?


        public var dataTaskDidReceiveResponseWithCompletion: ((NSURLSession, NSURLSessionDataTask, NSURLResponse, NSURLSessionResponseDisposition -> Void) -> Void)?

        public var dataTaskDidBecomeDownloadTask: ((NSURLSession, NSURLSessionDataTask, NSURLSessionDownloadTask) -> Void)?

        public var dataTaskDidReceiveData: ((NSURLSession, NSURLSessionDataTask, NSData) -> Void)?

        public var dataTaskWillCacheResponse: ((NSURLSession, NSURLSessionDataTask, NSCachedURLResponse) -> NSCachedURLResponse?)?


        public var dataTaskWillCacheResponseWithCompletion: ((NSURLSession, NSURLSessionDataTask, NSCachedURLResponse, NSCachedURLResponse? -> Void) -> Void)?


        public func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            didReceiveResponse response: NSURLResponse,
            completionHandler: NSURLSessionResponseDisposition -> Void)
        {
            guard dataTaskDidReceiveResponseWithCompletion == nil else {
                dataTaskDidReceiveResponseWithCompletion?(session, dataTask, response, completionHandler)
                return
            }

            var disposition: NSURLSessionResponseDisposition = .Allow

            if let dataTaskDidReceiveResponse = dataTaskDidReceiveResponse {
                disposition = dataTaskDidReceiveResponse(session, dataTask, response)
            }

            completionHandler(disposition)
        }

        public func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            didBecomeDownloadTask downloadTask: NSURLSessionDownloadTask)
        {
            if let dataTaskDidBecomeDownloadTask = dataTaskDidBecomeDownloadTask {
                dataTaskDidBecomeDownloadTask(session, dataTask, downloadTask)
            } else {
                let downloadDelegate = Request.DownloadTaskDelegate(task: downloadTask)
                self[downloadTask] = downloadDelegate
            }
        }

        public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
            if let dataTaskDidReceiveData = dataTaskDidReceiveData {
                dataTaskDidReceiveData(session, dataTask, data)
            } else if let delegate = self[dataTask] as? Request.DataTaskDelegate {
                delegate.URLSession(session, dataTask: dataTask, didReceiveData: data)
            }
        }


        public func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            willCacheResponse proposedResponse: NSCachedURLResponse,
            completionHandler: NSCachedURLResponse? -> Void)
        {
            guard dataTaskWillCacheResponseWithCompletion == nil else {
                dataTaskWillCacheResponseWithCompletion?(session, dataTask, proposedResponse, completionHandler)
                return
            }

            if let dataTaskWillCacheResponse = dataTaskWillCacheResponse {
                completionHandler(dataTaskWillCacheResponse(session, dataTask, proposedResponse))
            } else if let delegate = self[dataTask] as? Request.DataTaskDelegate {
                delegate.URLSession(
                    session,
                    dataTask: dataTask,
                    willCacheResponse: proposedResponse,
                    completionHandler: completionHandler
                )
            } else {
                completionHandler(proposedResponse)
            }
        }

        public var downloadTaskDidFinishDownloadingToURL: ((NSURLSession, NSURLSessionDownloadTask, NSURL) -> Void)?

        public var downloadTaskDidWriteData: ((NSURLSession, NSURLSessionDownloadTask, Int64, Int64, Int64) -> Void)?

        public var downloadTaskDidResumeAtOffset: ((NSURLSession, NSURLSessionDownloadTask, Int64, Int64) -> Void)?

        public func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didFinishDownloadingToURL location: NSURL)
        {
            if let downloadTaskDidFinishDownloadingToURL = downloadTaskDidFinishDownloadingToURL {
                downloadTaskDidFinishDownloadingToURL(session, downloadTask, location)
            } else if let delegate = self[downloadTask] as? Request.DownloadTaskDelegate {
                delegate.URLSession(session, downloadTask: downloadTask, didFinishDownloadingToURL: location)
            }
        }


        public func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64)
        {
            if let downloadTaskDidWriteData = downloadTaskDidWriteData {
                downloadTaskDidWriteData(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
            } else if let delegate = self[downloadTask] as? Request.DownloadTaskDelegate {
                delegate.URLSession(
                    session,
                    downloadTask: downloadTask,
                    didWriteData: bytesWritten,
                    totalBytesWritten: totalBytesWritten,
                    totalBytesExpectedToWrite: totalBytesExpectedToWrite
                )
            }
        }

        public func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didResumeAtOffset fileOffset: Int64,
            expectedTotalBytes: Int64)
        {
            if let downloadTaskDidResumeAtOffset = downloadTaskDidResumeAtOffset {
                downloadTaskDidResumeAtOffset(session, downloadTask, fileOffset, expectedTotalBytes)
            } else if let delegate = self[downloadTask] as? Request.DownloadTaskDelegate {
                delegate.URLSession(
                    session,
                    downloadTask: downloadTask,
                    didResumeAtOffset: fileOffset,
                    expectedTotalBytes: expectedTotalBytes
                )
            }
        }


        var _streamTaskReadClosed: Any?
        var _streamTaskWriteClosed: Any?
        var _streamTaskBetterRouteDiscovered: Any?
        var _streamTaskDidBecomeInputStream: Any?

        // MARK: - NSObject

        public override func respondsToSelector(selector: Selector) -> Bool {
            #if !os(OSX)
                if selector == #selector(NSURLSessionDelegate.URLSessionDidFinishEventsForBackgroundURLSession(_:)) {
                    return sessionDidFinishEventsForBackgroundURLSession != nil
                }
            #endif

            switch selector {
            case #selector(NSURLSessionDelegate.URLSession(_:didBecomeInvalidWithError:)):
                return sessionDidBecomeInvalidWithError != nil
            case #selector(NSURLSessionDelegate.URLSession(_:didReceiveChallenge:completionHandler:)):
                return (sessionDidReceiveChallenge != nil  || sessionDidReceiveChallengeWithCompletion != nil)
            case #selector(NSURLSessionTaskDelegate.URLSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)):
                return (taskWillPerformHTTPRedirection != nil || taskWillPerformHTTPRedirectionWithCompletion != nil)
            case #selector(NSURLSessionDataDelegate.URLSession(_:dataTask:didReceiveResponse:completionHandler:)):
                return (dataTaskDidReceiveResponse != nil || dataTaskDidReceiveResponseWithCompletion != nil)
            default:
                return self.dynamicType.instancesRespondToSelector(selector)
            }
        }
    }
}
