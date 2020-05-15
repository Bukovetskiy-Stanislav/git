
import Alamofire
import Foundation
import UIKit

extension UIButton {

    // MARK: - Private - AssociatedKeys

    private struct AssociatedKeys {
        static var ImageDownloaderKey = "af_UIButton.ImageDownloader"
        static var SharedImageDownloaderKey = "af_UIButton.SharedImageDownloader"
        static var ImageReceiptsKey = "af_UIButton.ImageReceipts"
        static var BackgroundImageReceiptsKey = "af_UIButton.BackgroundImageReceipts"
    }

    // MARK: - Properties
    public var af_imageDownloader: ImageDownloader? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.ImageDownloaderKey) as? ImageDownloader
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.ImageDownloaderKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    public class var af_sharedImageDownloader: ImageDownloader {
        get {
            guard let
                downloader = objc_getAssociatedObject(self, &AssociatedKeys.SharedImageDownloaderKey) as? ImageDownloader
            else {
                return ImageDownloader.defaultInstance
            }

            return downloader
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.SharedImageDownloaderKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var imageRequestReceipts: [UInt: RequestReceipt] {
        get {
            guard let
                receipts = objc_getAssociatedObject(self, &AssociatedKeys.ImageReceiptsKey) as? [UInt: RequestReceipt]
            else {
                return [:]
            }

            return receipts
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.ImageReceiptsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var backgroundImageRequestReceipts: [UInt: RequestReceipt] {
        get {
            guard let
                receipts = objc_getAssociatedObject(self, &AssociatedKeys.BackgroundImageReceiptsKey) as? [UInt: RequestReceipt]
            else {
                return [:]
            }

            return receipts
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.BackgroundImageReceiptsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: - Image Downloads


    public func af_setImageForState(
        state: UIControlState,
        URL: NSURL,
        placeHolderImage: UIImage? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        completion: (Response<UIImage, NSError> -> Void)? = nil)
    {
        af_setImageForState(state,
            URLRequest: URLRequestWithURL(URL),
            placeholderImage: placeHolderImage,
            progress: progress,
            progressQueue: progressQueue,
            completion: completion
        )
    }


    public func af_setImageForState(
        state: UIControlState,
        URLRequest: URLRequestConvertible,
        placeholderImage: UIImage? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        completion: (Response<UIImage, NSError> -> Void)? = nil)
    {
        guard !isImageURLRequest(URLRequest, equalToActiveRequestURLForState: state) else { return }

        af_cancelImageRequestForState(state)

        let imageDownloader = af_imageDownloader ?? UIButton.af_sharedImageDownloader
        let imageCache = imageDownloader.imageCache

        // Use the image from the image cache if it exists
        if let image = imageCache?.imageForRequest(URLRequest.URLRequest, withAdditionalIdentifier: nil) {
            let response = Response<UIImage, NSError>(
                request: URLRequest.URLRequest,
                response: nil,
                data: nil,
                result: .Success(image)
            )

            completion?(response)
            setImage(image, forState: state)

            return
        }

        // Set the placeholder since we're going to have to download
        if let placeholderImage = placeholderImage { self.setImage(placeholderImage, forState: state)  }

        // Generate a unique download id to check whether the active request has changed while downloading
        let downloadID = NSUUID().UUIDString

        // Download the image, then set the image for the control state
        let requestReceipt = imageDownloader.downloadImage(
            URLRequest: URLRequest,
            receiptID: downloadID,
            filter: nil,
            progress: progress,
            progressQueue: progressQueue,
            completion: { [weak self] response in
                guard let strongSelf = self else { return }

                completion?(response)

                guard
                    strongSelf.isImageURLRequest(response.request, equalToActiveRequestURLForState: state) &&
                    strongSelf.imageRequestReceiptForState(state)?.receiptID == downloadID
                else {
                    return
                }

                if let image = response.result.value {
                    strongSelf.setImage(image, forState: state)
                }

                strongSelf.setImageRequestReceipt(nil, forState: state)
            }
        )

        setImageRequestReceipt(requestReceipt, forState: state)
    }


    public func af_cancelImageRequestForState(state: UIControlState) {
        guard let receipt = imageRequestReceiptForState(state) else { return }

        let imageDownloader = af_imageDownloader ?? UIButton.af_sharedImageDownloader
        imageDownloader.cancelRequestForRequestReceipt(receipt)

        setImageRequestReceipt(nil, forState: state)
    }

    // MARK: - Background Image Downloads


    public func af_setBackgroundImageForState(
        state: UIControlState,
        URL: NSURL,
        placeHolderImage: UIImage? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        completion: (Response<UIImage, NSError> -> Void)? = nil)
    {
        af_setBackgroundImageForState(state,
            URLRequest: URLRequestWithURL(URL),
            placeholderImage: placeHolderImage,
            completion: completion)
    }


    public func af_setBackgroundImageForState(
        state: UIControlState,
        URLRequest: URLRequestConvertible,
        placeholderImage: UIImage? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        completion: (Response<UIImage, NSError> -> Void)? = nil)
    {
        guard !isImageURLRequest(URLRequest, equalToActiveRequestURLForState: state) else { return }

        af_cancelBackgroundImageRequestForState(state)

        let imageDownloader = af_imageDownloader ?? UIButton.af_sharedImageDownloader
        let imageCache = imageDownloader.imageCache

        // Use the image from the image cache if it exists
        if let image = imageCache?.imageForRequest(URLRequest.URLRequest, withAdditionalIdentifier: nil) {
            let response = Response<UIImage, NSError>(
                request: URLRequest.URLRequest,
                response: nil,
                data: nil,
                result: .Success(image)
            )

            completion?(response)
            setBackgroundImage(image, forState: state)

            return
        }

        // Set the placeholder since we're going to have to download
        if let placeholderImage = placeholderImage { self.setBackgroundImage(placeholderImage, forState: state)  }

        // Generate a unique download id to check whether the active request has changed while downloading
        let downloadID = NSUUID().UUIDString

        // Download the image, then set the image for the control state
        let requestReceipt = imageDownloader.downloadImage(
            URLRequest: URLRequest,
            receiptID: downloadID,
            progress: progress,
            progressQueue: progressQueue,
            filter: nil,
            completion: { [weak self] response in
                guard let strongSelf = self else { return }

                completion?(response)

                guard
                    strongSelf.isBackgroundImageURLRequest(response.request, equalToActiveRequestURLForState: state) &&
                    strongSelf.backgroundImageRequestReceiptForState(state)?.receiptID == downloadID
                else {
                    return
                }

                if let image = response.result.value {
                    strongSelf.setBackgroundImage(image, forState: state)
                }

                strongSelf.setBackgroundImageRequestReceipt(nil, forState: state)
            }
        )

        setBackgroundImageRequestReceipt(requestReceipt, forState: state)
    }


    public func af_cancelBackgroundImageRequestForState(state: UIControlState) {
        guard let receipt = backgroundImageRequestReceiptForState(state) else { return }

        let imageDownloader = af_imageDownloader ?? UIButton.af_sharedImageDownloader
        imageDownloader.cancelRequestForRequestReceipt(receipt)

        setBackgroundImageRequestReceipt(nil, forState: state)
    }

    // MARK: - Internal - Image Request Receipts

    func imageRequestReceiptForState(state: UIControlState) -> RequestReceipt? {
        guard let receipt = imageRequestReceipts[state.rawValue] else { return nil }
        return receipt
    }

    func setImageRequestReceipt(receipt: RequestReceipt?, forState state: UIControlState) {
        var receipts = imageRequestReceipts
        receipts[state.rawValue] = receipt

        imageRequestReceipts = receipts
    }

    // MARK: - Internal - Background Image Request Receipts

    func backgroundImageRequestReceiptForState(state: UIControlState) -> RequestReceipt? {
        guard let receipt = backgroundImageRequestReceipts[state.rawValue] else { return nil }
        return receipt
    }

    func setBackgroundImageRequestReceipt(receipt: RequestReceipt?, forState state: UIControlState) {
        var receipts = backgroundImageRequestReceipts
        receipts[state.rawValue] = receipt

        backgroundImageRequestReceipts = receipts
    }

    // MARK: - Private - URL Request Helpers

    private func isImageURLRequest(
        URLRequest: URLRequestConvertible?,
        equalToActiveRequestURLForState state: UIControlState)
        -> Bool
    {
        if let
            currentRequest = imageRequestReceiptForState(state)?.request.task.originalRequest
            where currentRequest.URLString == URLRequest?.URLRequest.URLString
        {
            return true
        }

        return false
    }

    private func isBackgroundImageURLRequest(
        URLRequest: URLRequestConvertible?,
        equalToActiveRequestURLForState state: UIControlState)
        -> Bool
    {
        if let
            currentRequest = backgroundImageRequestReceiptForState(state)?.request.task.originalRequest
            where currentRequest.URLString == URLRequest?.URLRequest.URLString
        {
            return true
        }

        return false
    }

    private func URLRequestWithURL(URL: NSURL) -> NSURLRequest {
        let mutableURLRequest = NSMutableURLRequest(URL: URL)

        for mimeType in Request.acceptableImageContentTypes {
            mutableURLRequest.addValue(mimeType, forHTTPHeaderField: "Accept")
        }

        return mutableURLRequest
    }
}
