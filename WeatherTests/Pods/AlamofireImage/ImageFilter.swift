

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(OSX)
import Cocoa
#endif

// MARK: ImageFilter


public protocol ImageFilter {
    var filter: Image -> Image { get }


    var identifier: String { get }
}

extension ImageFilter {

    public var identifier: String { return "\(self.dynamicType)" }
}

// MARK: - Sizable


public protocol Sizable {
    /// The size of the type.
    var size: CGSize { get }
}

extension ImageFilter where Self: Sizable {
    public var identifier: String {
        let width = Int64(round(size.width))
        let height = Int64(round(size.height))

        return "\(self.dynamicType)-size:(\(width)x\(height))"
    }
}

// MARK: - Roundable
public protocol Roundable {
    /// The radius of the type.
    var radius: CGFloat { get }
}

extension ImageFilter where Self: Roundable {
    public var identifier: String {
        let radius = Int64(round(self.radius))
        return "\(self.dynamicType)-radius:(\(radius))"
    }
}

// MARK: - DynamicImageFilter


public struct DynamicImageFilter: ImageFilter {

    public let identifier: String


    public let filter: Image -> Image


    public init(_ identifier: String, filter: Image -> Image) {
        self.identifier = identifier
        self.filter = filter
    }
}

// MARK: - CompositeImageFilter

public protocol CompositeImageFilter: ImageFilter {
    /// The image filters to apply to the image in sequential order.
    var filters: [ImageFilter] { get }
}

public extension CompositeImageFilter {
    var identifier: String {
        return filters.map { $0.identifier }.joinWithSeparator("_")
    }
    var filter: Image -> Image {
        return { image in
            return self.filters.reduce(image) { $1.filter($0) }
        }
    }
}

// MARK: - DynamicCompositeImageFilter

public struct DynamicCompositeImageFilter: CompositeImageFilter {
    /// The image filters to apply to the image in sequential order.
    public let filters: [ImageFilter]


    public init(_ filters: [ImageFilter]) {
        self.filters = filters
    }

    public init(_ filters: ImageFilter...) {
        self.init(filters)
    }
}

#if os(iOS) || os(tvOS) || os(watchOS)


public struct ScaledToSizeFilter: ImageFilter, Sizable {
    /// The size of the filter.
    public let size: CGSize


    public init(size: CGSize) {
        self.size = size
    }

    public var filter: Image -> Image {
        return { image in
            return image.af_imageScaledToSize(self.size)
        }
    }
}

// MARK: -

public struct AspectScaledToFitSizeFilter: ImageFilter, Sizable {
    /// The size of the filter.
    public let size: CGSize


    public init(size: CGSize) {
        self.size = size
    }

    public var filter: Image -> Image {
        return { image in
            return image.af_imageAspectScaledToFitSize(self.size)
        }
    }
}

// MARK: -

public struct AspectScaledToFillSizeFilter: ImageFilter, Sizable {
    /// The size of the filter.
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    /// The filter closure used to create the modified representation of the given image.
    public var filter: Image -> Image {
        return { image in
            return image.af_imageAspectScaledToFillSize(self.size)
        }
    }
}

// MARK: -

public struct RoundedCornersFilter: ImageFilter, Roundable {
    /// The radius of the filter.
    public let radius: CGFloat

    public let divideRadiusByImageScale: Bool


    public init(radius: CGFloat, divideRadiusByImageScale: Bool = false) {
        self.radius = radius
        self.divideRadiusByImageScale = divideRadiusByImageScale
    }

    /// The filter closure used to create the modified representation of the given image.
    public var filter: Image -> Image {
        return { image in
            return image.af_imageWithRoundedCornerRadius(
                self.radius,
                divideRadiusByImageScale: self.divideRadiusByImageScale
            )
        }
    }

    public var identifier: String {
        let radius = Int64(round(self.radius))
        return "\(self.dynamicType)-radius:(\(radius))-divided:(\(divideRadiusByImageScale))"
    }
}

// MARK: -

public struct CircleFilter: ImageFilter {

    public init() {}

    public var filter: Image -> Image {
        return { image in
            return image.af_imageRoundedIntoCircle()
        }
    }
}

// MARK: -

#if os(iOS) || os(tvOS)

public struct BlurFilter: ImageFilter {
    /// The blur radius of the filter.
    let blurRadius: UInt


    public init(blurRadius: UInt = 10) {
        self.blurRadius = blurRadius
    }

    public var filter: Image -> Image {
        return { image in
            let parameters = ["inputRadius": self.blurRadius]
            return image.af_imageWithAppliedCoreImageFilter("CIGaussianBlur", filterParameters: parameters) ?? image
        }
    }
}

#endif


public struct ScaledToSizeWithRoundedCornersFilter: CompositeImageFilter {

    public init(size: CGSize, radius: CGFloat, divideRadiusByImageScale: Bool = false) {
        self.filters = [
            ScaledToSizeFilter(size: size),
            RoundedCornersFilter(radius: radius, divideRadiusByImageScale: divideRadiusByImageScale)
        ]
    }

    /// The image filters to apply to the image in sequential order.
    public let filters: [ImageFilter]
}

// MARK: -

.
public struct AspectScaledToFillSizeWithRoundedCornersFilter: CompositeImageFilter {

    public init(size: CGSize, radius: CGFloat, divideRadiusByImageScale: Bool = false) {
        self.filters = [
            AspectScaledToFillSizeFilter(size: size),
            RoundedCornersFilter(radius: radius, divideRadiusByImageScale: divideRadiusByImageScale)
        ]
    }

    /// The image filters to apply to the image in sequential order.
    public let filters: [ImageFilter]
}

// MARK: -

public struct ScaledToSizeCircleFilter: CompositeImageFilter {

    public init(size: CGSize) {
        self.filters = [ScaledToSizeFilter(size: size), CircleFilter()]
    }

    /// The image filters to apply to the image in sequential order.
    public let filters: [ImageFilter]
}

// MARK: -


public struct AspectScaledToFillSizeCircleFilter: CompositeImageFilter {

    public init(size: CGSize) {
        self.filters = [AspectScaledToFillSizeFilter(size: size), CircleFilter()]
    }

    public let filters: [ImageFilter]
}

#endif
