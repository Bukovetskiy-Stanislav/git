
import Alamofire
import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(OSX)
import Cocoa
#endif

// MARK: ImageCache

/// The `ImageCache` protocol defines a set of APIs for adding, removing and fetching images from a cache.
public protocol ImageCache {
    /// Adds the image to the cache with the given identifier.
    func addImage(image: Image, withIdentifier identifier: String)

    /// Removes the image from the cache matching the given identifier.
    func removeImageWithIdentifier(identifier: String) -> Bool

    /// Removes all images stored in the cache.
    func removeAllImages() -> Bool

    /// Returns the image in the cache associated with the given identifier.
    func imageWithIdentifier(identifier: String) -> Image?
}


public protocol ImageRequestCache: ImageCache {
    /// Adds the image to the cache using an identifier created from the request and additional identifier.
    func addImage(image: Image, forRequest request: NSURLRequest, withAdditionalIdentifier identifier: String?)

    /// Removes the image from the cache using an identifier created from the request and additional identifier.
    func removeImageForRequest(request: NSURLRequest, withAdditionalIdentifier identifier: String?) -> Bool

    /// Returns the image from the cache associated with an identifier created from the request and additional identifier.
    func imageForRequest(request: NSURLRequest, withAdditionalIdentifier identifier: String?) -> Image?
}

// MARK: -


public class AutoPurgingImageCache: ImageRequestCache {
    private class CachedImage {
        let image: Image
        let identifier: String
        let totalBytes: UInt64
        var lastAccessDate: NSDate

        init(_ image: Image, identifier: String) {
            self.image = image
            self.identifier = identifier
            self.lastAccessDate = NSDate()

            self.totalBytes = {
                #if os(iOS) || os(tvOS) || os(watchOS)
                    let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                #elseif os(OSX)
                    let size = CGSize(width: image.size.width, height: image.size.height)
                #endif

                let bytesPerPixel: CGFloat = 4.0
                let bytesPerRow = size.width * bytesPerPixel
                let totalBytes = UInt64(bytesPerRow) * UInt64(size.height)

                return totalBytes
            }()
        }

        func accessImage() -> Image {
            lastAccessDate = NSDate()
            return image
        }
    }

    // MARK: Properties

    /// The current total memory usage in bytes of all images stored within the cache.
    public var memoryUsage: UInt64 {
        var memoryUsage: UInt64 = 0
        dispatch_sync(synchronizationQueue) { memoryUsage = self.currentMemoryUsage }

        return memoryUsage
    }

    /// The total memory capacity of the cache in bytes.
    public let memoryCapacity: UInt64

    /// The preferred memory usage after purge in bytes. During a purge, images will be purged until the memory 
    /// capacity drops below this limit.
    public let preferredMemoryUsageAfterPurge: UInt64

    private let synchronizationQueue: dispatch_queue_t
    private var cachedImages: [String: CachedImage]
    private var currentMemoryUsage: UInt64

    // MARK: Initialization


    public init(memoryCapacity: UInt64 = 100_000_000, preferredMemoryUsageAfterPurge: UInt64 = 60_000_000) {
        self.memoryCapacity = memoryCapacity
        self.preferredMemoryUsageAfterPurge = preferredMemoryUsageAfterPurge

        precondition(
            memoryCapacity >= preferredMemoryUsageAfterPurge,
            "The `memoryCapacity` must be greater than or equal to `preferredMemoryUsageAfterPurge`"
        )

        self.cachedImages = [:]
        self.currentMemoryUsage = 0

        self.synchronizationQueue = {
            let name = String(format: "com.alamofire.autopurgingimagecache-%08%08", arc4random(), arc4random())
            return dispatch_queue_create(name, DISPATCH_QUEUE_CONCURRENT)
        }()

        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().addObserver(
                self,
                selector: #selector(AutoPurgingImageCache.removeAllImages),
                name: UIApplicationDidReceiveMemoryWarningNotification,
                object: nil
            )
        #endif
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }


    public func addImage(image: Image, forRequest request: NSURLRequest, withAdditionalIdentifier identifier: String? = nil) {
        let requestIdentifier = imageCacheKeyFromURLRequest(request, withAdditionalIdentifier: identifier)
        addImage(image, withIdentifier: requestIdentifier)
    }


    public func addImage(image: Image, withIdentifier identifier: String) {
        dispatch_barrier_async(synchronizationQueue) {
            let cachedImage = CachedImage(image, identifier: identifier)

            if let previousCachedImage = self.cachedImages[identifier] {
                self.currentMemoryUsage -= previousCachedImage.totalBytes
            }

            self.cachedImages[identifier] = cachedImage
            self.currentMemoryUsage += cachedImage.totalBytes
        }

        dispatch_barrier_async(synchronizationQueue) {
            if self.currentMemoryUsage > self.memoryCapacity {
                let bytesToPurge = self.currentMemoryUsage - self.preferredMemoryUsageAfterPurge

                var sortedImages = [CachedImage](self.cachedImages.values)
                sortedImages.sortInPlace {
                    let date1 = $0.lastAccessDate
                    let date2 = $1.lastAccessDate

                    return date1.timeIntervalSinceDate(date2) < 0.0
                }

                var bytesPurged = UInt64(0)

                for cachedImage in sortedImages {
                    self.cachedImages.removeValueForKey(cachedImage.identifier)
                    bytesPurged += cachedImage.totalBytes

                    if bytesPurged >= bytesToPurge {
                        break
                    }
                }

                self.currentMemoryUsage -= bytesPurged
            }
        }
    }

    // MARK: Remove Image from Cache


    public func removeImageForRequest(request: NSURLRequest, withAdditionalIdentifier identifier: String?) -> Bool {
        let requestIdentifier = imageCacheKeyFromURLRequest(request, withAdditionalIdentifier: identifier)
        return removeImageWithIdentifier(requestIdentifier)
    }


    public func removeImageWithIdentifier(identifier: String) -> Bool {
        var removed = false

        dispatch_barrier_async(synchronizationQueue) {
            if let cachedImage = self.cachedImages.removeValueForKey(identifier) {
                self.currentMemoryUsage -= cachedImage.totalBytes
                removed = true
            }
        }

        return removed
    }


    @objc public func removeAllImages() -> Bool {
        var removed = false

        dispatch_sync(synchronizationQueue) {
            if !self.cachedImages.isEmpty {
                self.cachedImages.removeAll()
                self.currentMemoryUsage = 0

                removed = true
            }
        }

        return removed
    }


    public func imageForRequest(request: NSURLRequest, withAdditionalIdentifier identifier: String? = nil) -> Image? {
        let requestIdentifier = imageCacheKeyFromURLRequest(request, withAdditionalIdentifier: identifier)
        return imageWithIdentifier(requestIdentifier)
    }


    public func imageWithIdentifier(identifier: String) -> Image? {
        var image: Image?

        dispatch_sync(synchronizationQueue) {
            if let cachedImage = self.cachedImages[identifier] {
                image = cachedImage.accessImage()
            }
        }

        return image
    }

    // MARK: Private - Helper Methods

    private func imageCacheKeyFromURLRequest(
        request: NSURLRequest,
        withAdditionalIdentifier identifier: String?)
        -> String
    {
        var key = request.URLString

        if let identifier = identifier {
            key += "-\(identifier)"
        }

        return key
    }
}
