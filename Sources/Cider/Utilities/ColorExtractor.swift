import AppKit
import SwiftUI

/// Extracts dominant/average color from an NSImage
enum ColorExtractor {
    /// Returns the average color of an image, useful for creating glow effects
    static func averageColor(from image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .white
        }

        // Scale down for performance
        let size = 20
        let width = size
        let height = size

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .white
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let a = CGFloat(rawData[index + 3]) / 255.0

                // Only count non-transparent pixels
                if a > 0.3 {
                    totalR += CGFloat(rawData[index]) / 255.0 * a
                    totalG += CGFloat(rawData[index + 1]) / 255.0 * a
                    totalB += CGFloat(rawData[index + 2]) / 255.0 * a
                    count += a
                }
            }
        }

        guard count > 0 else { return .white }

        let avgR = totalR / count
        let avgG = totalG / count
        let avgB = totalB / count

        // Boost saturation slightly for more vibrant glow
        return Color(
            red: min(avgR * 1.1, 1.0),
            green: min(avgG * 1.1, 1.0),
            blue: min(avgB * 1.1, 1.0)
        )
    }

    /// Returns a more vibrant/saturated version of the average color
    static func vibrantColor(from image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .blue
        }

        // Scale down for performance
        let size = 20
        let width = size
        let height = size

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .blue
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Find the most saturated color
        var bestColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.5, 0.5, 1.0)
        var bestSaturation: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let a = CGFloat(rawData[index + 3]) / 255.0

                if a > 0.5 {
                    let r = CGFloat(rawData[index]) / 255.0
                    let g = CGFloat(rawData[index + 1]) / 255.0
                    let b = CGFloat(rawData[index + 2]) / 255.0

                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    let saturation = maxC > 0 ? (maxC - minC) / maxC : 0

                    // Prefer saturated colors that aren't too dark or too light
                    let brightness = (r + g + b) / 3
                    if saturation > bestSaturation && brightness > 0.2 && brightness < 0.9 {
                        bestSaturation = saturation
                        bestColor = (r, g, b)
                    }
                }
            }
        }

        // If no saturated color found, use average
        if bestSaturation < 0.1 {
            return averageColor(from: image)
        }

        return Color(red: bestColor.r, green: bestColor.g, blue: bestColor.b)
    }
}
