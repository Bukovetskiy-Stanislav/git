

import Alamofire
import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(watchOS)
import UIKit
import WatchKit
#elseif os(OSX)
import Cocoa
#endif

extension Request {
    static var acceptableImageContentTypes: Set<String> = [
        "image/tiff",
        "image/jpeg",
        "image/gif",
        "image/png",
        "image/ico",
        "image/x-icon",
        "image/bmp",
        "image/x-bmp",
        "image/x-xbitmap",
        "image/x-ms-bmp",
        "image/x-win-bitmap"
    ]


    public class func addAcceptableImageContentTypes(contentTypes: Set<String>) {
        Request.acceptableImageContentTypes.unionInPlace(contentTypes)
    }


#if os(iOS) || os(tvOS) || os(watchOS)


    public class func imageResponseSerializer(
        imageScale imageScale: CGFloat = Request.imageScale,
        inflateResponseImage: Bool = true)
        -> ResponseSerializer<UIImage, NSError>
    {
        return ResponseSerializer { request, response, data, error in
            guard error == nil else { return .Failure(error!) }

            guard let validData = data where validData.length > 0 else {
                return .Failure(Request.imageDataError())
            }

            guard Request.validateContentTypeForRequest(request, response: response) else {
                return .Failure(Request.contentTypeValidationError())
            }

            do {
                let image = try Request.imageFromResponseData(validData, imageScale: imageScale)
                if inflateResponseImage { image.af_inflate() }

                return .Success(image)
            } catch {
                return .Failure(error as NSError)
            }
        }
    }


    public func responseImage(
        imageScale: CGFloat = Request.imageScale,
        inflateResponseImage: Bool = true,
        completionHandler: Response<Image, NSError> -> Void)
        -> Self
    {
        return response(
            responseSerializer: Request.imageResponseSerializer(
                imageScale: imageScale,
                inflateResponseImage: inflateResponseImage
            ),
            completionHandler: completionHandler
        )
    }

    private class func imageFromResponseData(data: NSData, imageScale: CGFloat) throws -> UIImage {
        if let image = UIImage.af_threadSafeImageWithData(data, scale: imageScale) {
            return image
        }

        throw imageDataError()
    }

    private class var imageScale: CGFloat {
        #if os(iOS) || os(tvOS)
            return UIScreen.mainScreen().scale
        #elseif os(watchOS)
            return WKInterfaceDevice.currentDevice().screenScale
        #endif
    }

