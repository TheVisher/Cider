import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Cider

struct BookmarkImageQualityTests {
    @Test("all-white screenshot is low information")
    func allWhiteScreenshotIsLowInformation() throws {
        let data = try pngData(width: 720, height: 405) { _, _ in
            (255, 255, 255)
        }

        #expect(BookmarkImageQuality.isLowInformationImageData(data))
    }

    @Test("varied screenshot is useful image data")
    func variedScreenshotIsUsefulImageData() throws {
        let data = try pngData(width: 720, height: 405) { x, y in
            (UInt8(x % 255), UInt8(y % 255), UInt8((x + y) % 255))
        }

        #expect(!BookmarkImageQuality.isLowInformationImageData(data))
    }

    @Test("solid non-blank image is useful image data")
    func solidNonBlankImageIsUsefulImageData() throws {
        let data = try pngData(width: 4, height: 4) { _, _ in
            (0, 255, 0)
        }

        #expect(!BookmarkImageQuality.isLowInformationImageData(data))
    }

    private func pngData(
        width: Int,
        height: Int,
        color: (Int, Int) -> (UInt8, UInt8, UInt8)
    ) throws -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let (red, green, blue) = color(x, y)
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue
                pixels[offset + 3] = 255
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
