import Foundation
import WebKit
import UniformTypeIdentifiers

/// WKURLSchemeHandler that serves vault files via the `cider-vault://` scheme.
///
/// The editor uses `cider-vault:///absolute/path/to/file` URLs for embedded
/// images. This lets WKWebView load vault files without needing `allowingReadAccessTo`
/// to cover both the app bundle and the vault directory simultaneously.
final class CiderVaultSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "CiderVaultSchemeHandler", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Missing request URL"])
            )
            return
        }
        let filePath = url.path
        let fileURL = URL(fileURLWithPath: filePath)

        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "CiderVaultSchemeHandler", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "File not found: \(filePath)"])
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
}
