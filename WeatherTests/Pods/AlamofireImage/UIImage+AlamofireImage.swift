.

import CoreGraphics
import Foundation
import UIKit

#if os(iOS) || os(tvOS)
import CoreImage
#endif

// MARK: Initialization

private let lock = NSLock()

extension UIImage {

    public static func af_threadSafeImageWithData(data: NSData) -> UIImage? {
        lock.lock()
        let image = UIImage(data: data)
        lock.unlock()

        return image
    }


    public static func af_threadSafeImageWithData(data: NSData, scale: CGFloat) -> UIImage? {
        lock.lock()
        let image = UIImage(data: data, scale: scale)
        lock.unlock()

        return image
    }
}

// MARK: - Inflation

extension UIImage {
    private struct AssociatedKeys {
        static var InflatedKey = "af_UIImage.Inflated"
    }

    /// Returns whether the image is inflated.
    public var af_inflated: Bool {
        get {
            if let inflated = objc_getAssociatedObject(self, &AssociatedKeys.InflatedKey) as? Bool {
                return inflated
            } else {
                return false
            }
        }
        set(inflated) {
            objc_setAssociatedObject(self, &AssociatedKeys.InflatedKey, inflated, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }


    public func af_inflate() {
        guard !af_inflated else { return }

        af_inflated = true
        CGDataProviderCopyData(CGImageGetDataProvider(CGImage))
    }
}

// MARK: - Alpha

extension UIImage {
    /// Returns whether the image contains an alpha component.
    public var af_containsAlphaComponent: Bool {
        let alphaInfo = CGImageGetAlphaInfo(CGImage)

        return (
            alphaInfo == .First ||
            alphaInfo == .Last ||
            alphaInfo == .PremultipliedFirst ||
            alphaInfo == .PremultipliedLast
        )
    }

    /// Returns whether the image is opaque.
    public var af_isOpaque: Bool { return !af_containsAlphaComponent }
}

// MARK: - Scaling

extension UIImage {

    public func af_imageScaledToSize(size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, af_isOpaque, 0.0)
        drawInRect(CGRect(origin: CGPointZero, size: size))

        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage
    }


    public func af_imageAspectScaledToFitSize(size: CGSize) -> UIImage {
        let imageAspectRatio = self.size.width / self.size.height
        let canvasAspectRatio = size.width / size.height

        var resizeFactor: CGFloat

        if imageAspectRatio > canvasAspectRatio {
            resizeFactor = size.width / self.size.width
        } else {
            resizeFactor = size.height / self.size.height
        }

        let scaledSize = CGSize(width: self.size.width * resizeFactor, height: self.size.height * resizeFactor)
        let origin = CGPoint(x: (size.width - scaledSize.width) / 2.0, y: (size.height - scaledSize.height) / 2.0)

        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        drawInRect(CGRect(origin: origin, size: scaledSize))

        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage
    }


    public func af_imageAspectScaledToFillSize(size: CGSize) -> UIImage {
        let imageAspectRatio = self.size.width / self.size.height
        let canvasAspectRatio = size.width / size.height

        var resizeFactor: CGFloat

        if imageAspectRatio > canvasAspectRatio {
            resizeFactor = size.height / self.size.height
        } else {
            resizeFactor = size.width / self.size.width
        }

        let scaledSize = CGSize(width: self.size.width * resizeFactor, height: self.size.height * resizeFactor)
        let origin = CGPoint(x: (size.width - scaledSize.width) / 2.0, y: (size.height - scaledSize.height) / 2.0)

        UIGraphicsBeginImageContextWithOptions(size, af_isOpaque, 0.0)
        drawInRect(CGRect(origin: origin, size: scaledSize))

        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage
    }
}

// MARK: - Rounded Corners

extension UIImage {

    public func af_imageWithRoundedCornerRadius(radius: CGFloat, divideRadiusByImageScale: Bool = false) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)

        let scaledRadius = divideRadiusByImageScale ? radius / scale : radius

        let clippingPath = UIBezierPath(roundedRect: CGRect(origin: CGPointZero, size: size), cornerRadius: scaledRadius)
        clippingPath.addClip()

        drawInRect(CGRect(origin: CGPointZero, size: size))

        let roundedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return roundedImage
    }


    public func af_imageRoundedIntoCircle() -> UIImage {
        let radius = min(size.width, size.height) / 2.0
        var squareImage = self

        if size.width != size.height {
            let squareDimension = min(size.width, size.height)
            let squareSize = CGSize(width: squareDimension, height: squareDimension)
            squareImage = af_imageAspectScaledToFillSize(squareSize)
        }

        UIGraphicsBeginImageContextWithOptions(squareImage.size, false, 0.0)

        let clippingPath = UIBezierPath(
            roundedRect: CGRect(origin: CGPointZero, size: squareImage.size),
            cornerRadius: radius
        )

        clippingPath.addClip()

        squareImage.drawInRect(CGRect(origin: CGPointZero, size: squareImage.size))

        let roundedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return roundedImage
    }
}

#if os(iOS) || os(tvOS)

// MARK: - Core Image Filters

extension UIImage {

    public func af_imageWithAppliedCoreImageFilter(
        filterName: String,
        filterParameters: [String: AnyObject]? = nil) -> UIImage?
    {
        var image: CoreImage.CIImage? = CIImage

        if image == nil, let CGImage = self.CGImage {
            image = CoreImage.CIImage(CGImage: CGImage)
        }

        guard let coreImage = image else { return nil }

        let context = CIContext(options: [kCIContextPriorityRequestLow: true])

        var parameters: [String: AnyObject] = filterParameters ?? [:]
        parameters[kCIInputImageKey] = coreImage

        guard let filter = CIFilter(name: filterName, withInputParameters: parameters) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }

        let cgImageRef = context.createCGImage(outputImage, fromRect: outputImage.extent)

        return UIImage(CGImage: cgImageRef, scale: scale, orientation: imageOrientation)
    }
}

#endif
