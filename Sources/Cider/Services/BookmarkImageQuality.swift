import CoreGraphics
import Foundation
import ImageIO

enum BookmarkImageQuality {
    private static let sampleMaxPixelSize = 32
    private static let lowRangeThreshold: CGFloat = 0.035
    private static let lowVarianceThreshold: CGFloat = 0.00025

    static func isLowInformationImageData(_ data: Data) -> Bool {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return false
        }
        return isLowInformationImage(source: source)
    }

    static func isLowInformationImage(at url: URL) -> Bool {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return false
        }
        return isLowInformationImage(source: source)
    }

    static func isLowInformationImage(_ image: CGImage) -> Bool {
        let width = min(sampleMaxPixelSize, image.width)
        let height = min(sampleMaxPixelSize, image.height)
        guard width > 0, height > 0 else { return true }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minLuminance = CGFloat.greatestFiniteMagnitude
        var maxLuminance = CGFloat.leastNormalMagnitude
        var sum: CGFloat = 0
        var sumSquares: CGFloat = 0
        var sampleCount: CGFloat = 0

        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = CGFloat(pixels[index + 3]) / 255
            guard alpha > 0.95 else { continue }

            let red = CGFloat(pixels[index]) / 255
            let green = CGFloat(pixels[index + 1]) / 255
            let blue = CGFloat(pixels[index + 2]) / 255
            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)

            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
            sum += luminance
            sumSquares += luminance * luminance
            sampleCount += 1
        }

        guard sampleCount > 0 else { return true }
        let mean = sum / sampleCount
        let variance = max(0, (sumSquares / sampleCount) - (mean * mean))
        let isNearBlankWhiteOrBlack = mean > 0.94 || mean < 0.06
        return isNearBlankWhiteOrBlack
            && (maxLuminance - minLuminance) < lowRangeThreshold
            && variance < lowVarianceThreshold
    }

    private static func isLowInformationImage(source: CGImageSource) -> Bool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: sampleMaxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        return isLowInformationImage(image)
    }
}
