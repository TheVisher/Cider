import Foundation
import Vision
import CoreGraphics

/// On-device OCR using the Vision framework.
/// Extracts text from bookmark thumbnail images so they become searchable.
struct OCRService {

    /// Extract all readable text from an image file.
    /// Returns nil if the image can't be read or contains no text.
    static func extractText(from imageURL: URL) async -> String? {
        await Task.detached(priority: .background) {
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let results = request.results, !results.isEmpty
            else { return nil }

            let text = results
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            return text.isEmpty ? nil : text
        }.value
    }
}
