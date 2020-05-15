

import Alamofire
import Foundation
import UIKit

extension UIImageView {

    // MARK: - ImageTransition

    public enum ImageTransition {
        case None
        case CrossDissolve(NSTimeInterval)
        case CurlDown(NSTimeInterval)
        case CurlUp(NSTimeInterval)
        case FlipFromBottom(NSTimeInterval)
        case FlipFromLeft(NSTimeInterval)
        case FlipFromRight(NSTimeInterval)
        case FlipFromTop(NSTimeInterval)
        case Custom(
            duration: NSTimeInterval,
            animationOptions: UIViewAnimationOptions,
            animations: (UIImageView, Image) -> Void,
            completion: (Bool -> Void)?
        )

        public var duration: NSTimeInterval {
            switch self {
            case None:
                return 0.0
            case CrossDissolve(let duration):
                return duration
            case CurlDown(let duration):
                return duration
            case CurlUp(let duration):
                return duration
            case FlipFromBottom(let duration):
                return duration
            case FlipFromLeft(let duration):
                return duration
            case FlipFromRight(let duration):
                return duration
            case FlipFromTop(let duration):
                return duration
            case Custom(let duration, _, _, _):
                return duration
            }
        }

        public var animationOptions: UIViewAnimationOptions {
            switch self {
            case None:
                return .TransitionNone
            case CrossDissolve:
                return .TransitionCrossDissolve
            case CurlDown:
                return .TransitionCurlDown
            case CurlUp:
                return .TransitionCurlUp
            case FlipFromBottom:
                return .TransitionFlipFromBottom
            case FlipFromLeft:
                return .TransitionFlipFromLeft
            case FlipFromRight:
                return .TransitionFlipFromRight
            case FlipFromTop:
                return .TransitionFlipFromTop
            case Custom(_, let animationOptions, _, _):
                return animationOptions
            }
        }

        public var animations: ((UIImageView, Image) -> Void) {
            switch self {
            case Custom(_, _, let animations, _):
                return animations
            default:
                return { $0.image = $1 }
            }
        }

        public var completion: (Bool -> Void)? {
            switch self {
            case Custom(_, _, _, let completion):
                return completion
            default:
                return nil
            }
        }
    }


    private struct AssociatedKeys {
        static var ImageDownloaderKey = "af_UIImageView.ImageDownloader"
        static var SharedImageDownloaderKey = "af_UIImageView.SharedImageDownloader"
        static var ActiveRequestReceiptKey = "af_UIImageView.ActiveRequestReceipt"
    }


    public var af_imageDownloader: ImageDownloader? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.ImageDownloaderKey) as? ImageDownloader
        }
        set(downloader) {
            objc_setAssociatedObject(self, &AssociatedKeys.ImageDownloaderKey, downloader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }


    public class var af_sharedImageDownloader: ImageDownloader {
        get {
            if let downloader = objc_getAssociatedObject(self, &AssociatedKeys.SharedImageDownloaderKey) as? ImageDownloader {
                return downloader
            } else {
                return ImageDownloader.defaultInstance
            }
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.SharedImageDownloaderKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var af_activeRequestReceipt: RequestReceipt? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.ActiveRequestReceiptKey) as? RequestReceipt
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.ActiveRequestReceiptKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: - Image Download


    public func af_setImageWithURL(
        URL: NSURL,
        placeholderImage: UIImage? = nil,
        filter: ImageFilter? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        imageTransition: ImageTransition = .None,
        runImageTransitionIfCached: Bool = false,
        completion: (Response<UIImage, NSError> -> Void)? = nil)
    {
        af_setImageWithURLRequest(
            URLRequestWithURL(URL),
            placeholderImage: placeholderImage,
            filter: filter,
            progress: progress,
            progressQueue: progressQueue,
            imageTransition: imageTransition,
            runImageTransitionIfCached: runImageTransitionIfCached,
            completion: completion
        )
    }


    public func af_setImageWithURLRequest(
        URLRequest: URLRequestConvertible,
        placeholderImage: UIImage? = nil,
        filter: ImageFilter? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: dispatch_queue_t = dispatch_get_main_queue(),
        imageTransition: ImageTransition = .None,
        runImageTransitionIfCached: Bool = false,
        completion: (Response<UIImage, NSError> -> Void)? = nil)
    {
        guard !isURLRequestURLEqualToActiveRequestURL(URLRequest) else { return }

        af_cancelImageRequest()

        let imageDownloader = af_imageDownloader ?? UIImageView.af_sharedImageDownloader
        let imageCache = imageDownloader.imageCache

        // Use the image from the image cache if it exists
        if let image = imageCache?.imageForRequest(URLRequest.URLRequest, withAdditionalIdentifier: filter?.identifier) {
            let response = Response<UIImage, NSError>(
                request: URLRequest.URLRequest,
                response: nil,
                data: nil,
                result: .Success(image)
            )

            completion?(response)

            if runImageTransitionIfCached {
                let tinyDelay = dispatch_time(DISPATCH_TIME_NOW, Int64(0.001 * Float(NSEC_PER_SEC)))

                // Need to let the runloop cycle for the placeholder image to take affect
                dispatch_after(tinyDelay, dispatch_get_main_queue()) {
                    self.runImageTransition(imageTransition, withImage: image)
                }
            } else {
                self.image = image
            }

            return
        }

        // Set the placeholder since we're going to have to download
        if let placeholderImage = placeholderImage { self.image = placeholderImage }

        // Generate a unique download id to check whether the active request has changed while downloading
        let downloadID = NSUUID().UUIDString

        // Download the image, then run the image transition or completion handler
        let requestReceipt = imageDownloader.downloadImage(
            URLRequest: URLRequest,
            receiptID: downloadID,
            filter: filter,
            progress: progress,
            progressQueue: progressQueue,
            completion: { [weak self] response in
                guard let strongSelf = self else { return }

                completion?(response)

                guard
                    strongSelf.isURLRequestURLEqualToActiveRequestURL(response.request) &&
                    strongSelf.af_activeRequestReceipt?.receiptID == downloadID
                else {
                    return
                }

                if let image = response.result.value {
                    strongSelf.runImageTransition(imageTransition, withImage: image)
                }

                strongSelf.af_activeRequestReceipt = nil
            }
        )

        af_activeRequestReceipt = requestReceipt
    }

    // MARK: - Image Download Cancellation

    /**
        Cancels the active download request, if one exists.
    */
    public func af_cancelImageRequest() {
        guard let activeRequestReceipt = af_activeRequestReceipt else { return }

        let imageDownloader = af_imageDownloader ?? UIImageView.af_sharedImageDownloader
        imageDownloader.cancelRequestForRequestReceipt(activeRequestReceipt)

        af_activeRequestReceipt = nil
    }


    public func runImageTransition(imageTransition: ImageTransition, withImage image: Image) {
        UIView.transitionWithView(
            self,
            duration: imageTransition.duration,
            options: imageTransition.animationOptions,
            animations: {
                imageTransition.animations(self, image)
            },
            completion: imageTransition.completion
        )
    }


    private func URLRequestWithURL(URL: NSURL) -> NSURLRequest {
        let mutableURLRequest = NSMutableURLRequest(URL: URL)

        for mimeType in Request.acceptableImageContentTypes {
            mutableURLRequest.addValue(mimeType, forHTTPHeaderField: "Accept")
        }

        return mutableURLRequest
    }

    private func isURLRequestURLEqualToActiveRequestURL(URLRequest: URLRequestConvertible?) -> Bool {
        if let
            currentRequest = af_activeRequestReceipt?.request.task.originalRequest
            where currentRequest.URLString == URLRequest?.URLRequest.URLString
        {
            return true
        }

        return false
    }
}
