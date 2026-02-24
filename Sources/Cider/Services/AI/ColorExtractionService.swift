import Foundation
import CoreGraphics
import AppKit

/// Extracts dominant colors from bookmark thumbnail images using pixel sampling.
/// No ML model required — works via CGImage pixel data.
struct ColorExtractionService {

    /// Extract dominant colors as hex strings (e.g. "#E23A4F").
    /// - Parameters:
    ///   - imageURL: Path to the thumbnail file
    ///   - count: Number of dominant colors to return (max 5)
    static func extractDominantColors(from imageURL: URL, count: Int = 3) async -> [String] {
        await Task.detached(priority: .background) {
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return [] }

            // Downsample to tiny grid for fast color analysis
            let sampleSize = 20
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var rawData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
            guard let context = CGContext(
                data: &rawData,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: sampleSize * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return [] }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

            // Collect RGBA pixels
            var buckets: [Int: Int] = [:]  // quantized color key → count
            for i in 0..<(sampleSize * sampleSize) {
                let offset = i * 4
                let r = rawData[offset]
                let g = rawData[offset + 1]
                let b = rawData[offset + 2]
                let a = rawData[offset + 3]
                guard a > 128 else { continue }  // skip transparent
                // Skip near-white and near-black (less interesting)
                let brightness = (Int(r) + Int(g) + Int(b)) / 3
                guard brightness > 20, brightness < 235 else { continue }
                // Quantize to buckets of ~16 values
                let key = (Int(r) >> 4) << 8 | (Int(g) >> 4) << 4 | (Int(b) >> 4)
                buckets[key, default: 0] += 1
            }

            let sorted = buckets.sorted { $0.value > $1.value }
            let topColors: [String] = sorted.prefix(count).map { (key, _) in
                let r = UInt8((key >> 8) & 0xF) * 17
                let g = UInt8((key >> 4) & 0xF) * 17
                let b = UInt8(key & 0xF) * 17
                return String(format: "#%02X%02X%02X", r, g, b)
            }
            return topColors
        }.value
    }
}
