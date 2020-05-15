
import Alamofire
import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(OSX)
import Cocoa
#endif


public class RequestReceipt {
    /// The download request created by the `ImageDownloader`.
    public let request: Request

    /// The unique identifier for the image filters and completion handlers when duplicate requests are made.
    public let receiptID: String

    init(request: Request, receiptID: String) {
        self.request = request
        self.receiptID = receiptID
    }
}


public class ImageDownloader {
    /// The completion handler closure used when an image download completes.
    public typealias CompletionHandler = Response<Image, NSError> -> Void

    /// The progress handler closure called periodically during an image download.
    public typealias ProgressHandler = (bytesRead: Int64, totalBytesRead: Int64, totalExpectedBytesToRead: Int64) -> Void


    public enum DownloadPrioritization {
        case FIFO, LIFO
    }

    class ResponseHandler {
        let identifier: String
        let request: Request
        var operations: [(id: String, filter: ImageFilter?, completion: CompletionHandler?)]

        init(request: Request, id: String, filter: ImageFilter?, completion: CompletionHandler?) {
            self.request = request
            self.identifier = ImageDownloader.identifierForURLRequest(request.request!)
            self.operations = [(id: id, filter: filter, completion: completion)]
        }
    }

    // MARK: - Properties

    /// The image cache used to store all downloaded images in.
    public let imageCache: ImageRequestCache?

    /// The credential used for authenticating each download request.
    public private(set) var credential: NSURLCredential?

    /// The underlying Alamofire `Manager` instance used to handle all download requests.
    public let sessionManager: Alamofire.Manager

    let downloadPrioritization: DownloadPrioritization
    let maximumActiveDownloads: Int

    var activeRequestCount = 0
    var queuedRequests: [Request] = []
    var responseHandlers: [String: ResponseHandler] = [:]

    private let synchronizationQueue: dispatch_queue_t = {
        let name = String(format: "com.alamofire.imagedownloader.synchronizationqueue-%08%08", arc4random(), arc4random())
        return dispatch_queue_create(name, DISPATCH_QUEUE_SERIAL)
    }()

    private let responseQueue: dispatch_queue_t = {
        let name = String(format: "com.alamofire.imagedownloader.responsequeue-%08%08", arc4random(), arc4random())
        return dispatch_queue_create(name, DISPATCH_QUEUE_CONCURRENT)
    }()

    // MARK: - Initialization

    /// The default instance of `ImageDownloader` initialized with default values.
    public static let defaultInstance = ImageDownloader()

    /**
        Creates a default `NSURLSessionConfiguration` with common usage parameter values.
    
        - returns: The default `NSURLSessionConfiguration` instance.
    */
    public class func defaultURLSessionConfiguration() -> NSURLSessionConfiguration {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()

        configuration.HTTPAdditionalHeaders = Manager.defaultHTTPHeaders
        configuration.HTTPShouldSetCookies = true
        configuration.HTTPShouldUsePipelining = false

        configuration.requestCachePolicy = .UseProtocolCachePolicy
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 60

        configuration.URLCache = ImageDownloader.defaultURLCache()

        return configuration
    }

    /**
        Creates a default `NSURLCache` with common usage parameter values.

        - returns: The default `NSURLCache` instance.
    */
    public class func defaultURLCache() -> NSURLCache {
        return NSURLCache(
            memoryCapacity: 20 * 1024 * 1024, // 20 MB
            diskCapacity: 150 * 1024 * 1024,  // 150 MB
            diskPath: "com.alamofire.imagedownloader"
        )
    }


    public init(
        configuration: NSURLSessionConfiguration = ImageDownloader.defaultURLSessionConfiguration(),
        downloadPrioritization: DownloadPrioritization = .FIFO,
        maximumActiveDownloads: Int = 4,
        imageCache: ImageRequestCache? = AutoPurgingImageCache())
    {
        self.sessionManager = Alamofire.Manager(configuration: configuration)
        self.sessionManager.startRequestsImmediately = false

        self.downloadPrioritization = downloadPrioritization
        self.maximumActiveDownloads = maximumActiveDownloads
        self.imageCache = imageCache
    }



    public init(
        sessionManager: Manager,
        downloadPrioritization: DownloadPrioritization = .FIFO,
        maximumActiveDownloads: Int = 4,
        imageCache: ImageRequestCache? = AutoPurgingImageCache())
    {
        self.sessionManager = sessionManager
        self.sessionManager.startRequestsImmediately = false

        self.downloadPrioritization = downloadPrioritization
        self.maximumActiveDownloads = maximumActiveDownloads
        self.imageCache = imageCache
    }

    // MARK: - Authentication


    public func addAuthentication(
        user user: String,
        password: String,
        persistence: NSURLCredentialPersistence = .ForSession)
    {
        let credential = NSURLCredential(user: user, password: password, persistence: persistence)
        addAuthentication(usingCredential: credential)
    }


    public func addAuthentication(usingCredential credential: NSURLCredential) {
        dispatch_sync(synchronizationQueue) {
            self.credential = credential
        }
    }


    public func downloadImage(
        URLRequest URLRequest: URLRequestConvertible,
        receiptID: String = NSUUID().UUIDString,
        filter: ImageFilter? = nil,
        progress: ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        completion: CompletionHandler?)
        -> RequestReceipt?
    {
        var request: Request!

        dispatch_sync(synchronizationQueue) {
            // 1) Append the filter and completion handler to a pre-existing request if it already exists
            let identifier = ImageDownloader.identifierForURLRequest(URLRequest)

            if let responseHandler = self.responseHandlers[identifier] {
                responseHandler.operations.append(id: receiptID, filter: filter, completion: completion)
                request = responseHandler.request
                return
            }

            // 2) Attempt to load the image from the image cache if the cache policy allows it
            switch URLRequest.URLRequest.cachePolicy {
            case .UseProtocolCachePolicy, .ReturnCacheDataElseLoad, .ReturnCacheDataDontLoad:
                if let image = self.imageCache?.imageForRequest(
                    URLRequest.URLRequest,
                    withAdditionalIdentifier: filter?.identifier)
                {
                    dispatch_async(dispatch_get_main_queue()) {
                        let response = Response<Image, NSError>(
                            request: URLRequest.URLRequest,
                            response: nil,
                            data: nil,
                            result: .Success(image)
                        )

                        completion?(response)
                    }

                    return
                }
            default:
                break
            }

            // 3) Create the request and set up authentication, validation and response serialization
            request = self.sessionManager.request(URLRequest)

            if let credential = self.credential {
                request.authenticate(usingCredential: credential)
            }

            request.validate()

            if let progress = progress {
                request.progress { bytesRead, totalBytesRead, totalExpectedBytesToRead in
                    dispatch_async(progressQueue) {
                        progress(
                            bytesRead: bytesRead,
                            totalBytesRead: totalBytesRead,
                            totalExpectedBytesToRead: totalExpectedBytesToRead
                        )
                    }
                }
            }

            request.response(
                queue: self.responseQueue,
                responseSerializer: Request.imageResponseSerializer(),
                completionHandler: { [weak self] response in
                    guard let strongSelf = self, let request = response.request else { return }

                    let responseHandler = strongSelf.safelyRemoveResponseHandlerWithIdentifier(identifier)

                    switch response.result {
                    case .Success(let image):
                        var filteredImages: [String: Image] = [:]

                        for (_, filter, completion) in responseHandler.operations {
                            var filteredImage: Image

                            if let filter = filter {
                                if let alreadyFilteredImage = filteredImages[filter.identifier] {
                                    filteredImage = alreadyFilteredImage
                                } else {
                                    filteredImage = filter.filter(image)
                                    filteredImages[filter.identifier] = filteredImage
                                }
                            } else {
                                filteredImage = image
                            }

                            strongSelf.imageCache?.addImage(
                                filteredImage,
                                forRequest: request,
                                withAdditionalIdentifier: filter?.identifier
                            )

                            dispatch_async(dispatch_get_main_queue()) {
                                let response = Response<Image, NSError>(
                                    request: response.request,
                                    response: response.response,
                                    data: response.data,
                                    result: .Success(filteredImage),
                                    timeline: response.timeline
                                )

                                completion?(response)
                            }
                        }
                    case .Failure:
                        for (_, _, completion) in responseHandler.operations {
                            dispatch_async(dispatch_get_main_queue()) { completion?(response) }
                        }
                    }

                    strongSelf.safelyDecrementActiveRequestCount()
                    strongSelf.safelyStartNextRequestIfNecessary()
                }
            )

            // 4) Store the response handler for use when the request completes
            let responseHandler = ResponseHandler(
                request: request,
                id: receiptID,
                filter: filter,
                completion: completion
            )

            self.responseHandlers[identifier] = responseHandler

            // 5) Either start the request or enqueue it depending on the current active request count
            if self.isActiveRequestCountBelowMaximumLimit() {
                self.startRequest(request)
            } else {
                self.enqueueRequest(request)
            }
        }

        if let request = request {
            return RequestReceipt(request: request, receiptID: receiptID)
        }

        return nil
    }


    public func downloadImages(
        URLRequests URLRequests: [URLRequestConvertible],
        filter: ImageFilter? = nil,
        progress: ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        completion: CompletionHandler? = nil)
        -> [RequestReceipt]
    {
        return URLRequests.flatMap {
            downloadImage(
                URLRequest: $0,
                filter: filter,
                progress: progress,
                progressQueue: progressQueue,
                completion: completion
            )
        }
    }


    public func cancelRequestForRequestReceipt(requestReceipt: RequestReceipt) {
        dispatch_sync(synchronizationQueue) {
            let identifier = ImageDownloader.identifierForURLRequest(requestReceipt.request.request!)
            guard let responseHandler = self.responseHandlers[identifier] else { return }

            if let index = responseHandler.operations.indexOf({ $0.id == requestReceipt.receiptID }) {
                let operation = responseHandler.operations.removeAtIndex(index)

                let response: Response<Image, NSError> = {
                    let URLRequest = requestReceipt.request.request!
                    let error: NSError = {
                        let failureReason = "ImageDownloader cancelled URL request: \(URLRequest.URLString)"
                        let userInfo = [NSLocalizedFailureReasonErrorKey: failureReason]
                        return NSError(domain: Error.Domain, code: NSURLErrorCancelled, userInfo: userInfo)
                    }()

                    return Response(request: URLRequest, response: nil, data: nil, result: .Failure(error))
                }()

                dispatch_async(dispatch_get_main_queue()) { operation.completion?(response) }
            }

            if responseHandler.operations.isEmpty && requestReceipt.request.task.state == .Suspended {
                requestReceipt.request.cancel()
            }
        }
    }

    // MARK: - Internal - Thread-Safe Request Methods

    func safelyRemoveResponseHandlerWithIdentifier(identifier: String) -> ResponseHandler {
        var responseHandler: ResponseHandler!

        dispatch_sync(synchronizationQueue) {
            responseHandler = self.responseHandlers.removeValueForKey(identifier)
        }

        return responseHandler
    }

    func safelyStartNextRequestIfNecessary() {
        dispatch_sync(synchronizationQueue) {
            guard self.isActiveRequestCountBelowMaximumLimit() else { return }

            while (!self.queuedRequests.isEmpty) {
                if let request = self.dequeueRequest() where request.task.state == .Suspended {
                    self.startRequest(request)
                    break
                }
            }
        }
    }

    func safelyDecrementActiveRequestCount() {
        dispatch_sync(self.synchronizationQueue) {
            if self.activeRequestCount > 0 {
                self.activeRequestCount -= 1
            }
        }
    }

    // MARK: - Internal - Non Thread-Safe Request Methods

    func startRequest(request: Request) {
        request.resume()
        activeRequestCount += 1
    }

    func enqueueRequest(request: Request) {
        switch downloadPrioritization {
        case .FIFO:
            queuedRequests.append(request)
        case .LIFO:
            queuedRequests.insert(request, atIndex: 0)
        }
    }

    func dequeueRequest() -> Request? {
        var request: Request?

        if !queuedRequests.isEmpty {
            request = queuedRequests.removeFirst()
        }

        return request
    }

    func isActiveRequestCountBelowMaximumLimit() -> Bool {
        return activeRequestCount < maximumActiveDownloads
    }

    static func identifierForURLRequest(URLRequest: URLRequestConvertible) -> String {
        return URLRequest.URLRequest.URLString
    }
}
