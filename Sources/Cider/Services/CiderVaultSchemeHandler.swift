import Foundation
import WebKit
import UniformTypeIdentifiers

/// WKURLSchemeHandler that serves vault files via the `cider-vault://` scheme.
///
/// The editor uses `cider-vault:///absolute/path/to/file` URLs for embedded
/// images. This lets WKWebView load vault files without needing `allowingReadAccessTo`
/// to cover both the app bundle and the vault directory simultaneously.
final class CiderVaultSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated private static let maxResponseBytes = 25 * 1024 * 1024
    nonisolated private static let allowedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "CiderVaultSchemeHandler", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Missing request URL"])
            )
            return
        }
        guard let fileURL = Self.allowedFileURL(for: url) else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "CiderVaultSchemeHandler", code: 403,
                        userInfo: [NSLocalizedDescriptionKey: "File is outside the allowed vault attachment roots"])
            )
            return
        }

        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              resourceValues.isRegularFile == true,
              (resourceValues.fileSize ?? 0) <= Self.maxResponseBytes,
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "CiderVaultSchemeHandler", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "File not found or too large"])
            )
            return
        }

        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No async work to cancel
    }

    nonisolated static func allowedFileURL(for url: URL) -> URL? {
        guard url.scheme == "cider-vault" else { return nil }
        let fileURL = URL(fileURLWithPath: url.path).standardizedFileURL
        guard allowedImageExtensions.contains(fileURL.pathExtension.lowercased()) else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard FileContainment.isContained(fileURL, inAny: allowedRoots()) else { return nil }
        return fileURL
    }

    nonisolated private static func allowedRoots() -> [URL] {
        [
            StoragePaths.cachedVaultDirectoryURL,
            StoragePaths.cachedDirectoryURL(for: .notes)
        ]
    }
}
