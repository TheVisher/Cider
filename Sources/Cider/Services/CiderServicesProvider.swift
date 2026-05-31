import AppKit

private func servicesImageSourceContext(
    sourceFile: String?,
    preferredFileExtension: String?
) -> CaptureSourceContext {
    let filename = sourceFile.map { URL(fileURLWithPath: $0).lastPathComponent }
    let mimeType = preferredFileExtension.map { "image/\($0.lowercased())" }
    let attachment = CaptureSourceContext.Attachment(
        filename: filename,
        mimeType: mimeType,
        localPath: sourceFile
    )
    let hasAttachmentMetadata = filename != nil || mimeType != nil || sourceFile != nil

    return CaptureSourceContext(
        surface: "macos_services",
        attachments: hasAttachmentMetadata ? [attachment] : []
    )
}

/// Handles macOS Services menu requests ("Send to Cider").
/// Two service entries: one for text (URLs + plain text), one for images.
/// Requires a proper .app bundle to appear in the Services menu.
@MainActor
final class CiderServicesProvider: NSObject {
    private let urlCaptureHandler: (String) throws -> CiderCaptureResult
    private let noteCaptureHandler: (String) throws -> CiderCaptureResult
    private let imageCaptureHandler: (Data, String?, String?) throws -> CiderCaptureResult
    private let toastHandler: (String, Bool) -> Void

    init(
        urlCaptureHandler: @escaping (String) throws -> CiderCaptureResult = {
            try CiderCaptureService().add(
                $0,
                sourceContext: CaptureSourceContext(surface: "macos_services", originalText: $0)
            )
        },
        noteCaptureHandler: @escaping (String) throws -> CiderCaptureResult = {
            try CiderCaptureService().addNoteCapture(
                title: nil,
                content: $0,
                folderID: nil,
                sourceContext: CaptureSourceContext(surface: "macos_services", originalText: $0)
            )
        },
        imageCaptureHandler: @escaping (Data, String?, String?) throws -> CiderCaptureResult = {
            try CiderCaptureService().addImageBookmarkCapture(
                title: "Image from Services",
                imageData: $0,
                preferredFileExtension: $1,
                sourceFile: $2,
                sourceContext: servicesImageSourceContext(sourceFile: $2, preferredFileExtension: $1)
            )
        },
        toastHandler: @escaping (String, Bool) -> Void = { message, isSuccess in
            NotificationCenter.default.post(
                name: .showBookmarkCaptureToast,
                object: nil,
                userInfo: ["message": message, "isSuccess": isSuccess]
            )
        }
    ) {
        self.urlCaptureHandler = urlCaptureHandler
        self.noteCaptureHandler = noteCaptureHandler
        self.imageCaptureHandler = imageCaptureHandler
        self.toastHandler = toastHandler
        super.init()
    }

    // MARK: - Text Service (public.utf8-plain-text)

    @objc nonisolated func sendTextToCider(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text = pasteboard.string(forType: .string)
        Task { @MainActor [weak self] in
            self?.handleText(text)
        }
    }

    func handleText(_ text: String?) {
        guard let text else { return }

        // Check if it looks like a URL
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let receipt: CaptureReceipt
            if let result = try? urlCaptureHandler(url.absoluteString) {
                receipt = CaptureReceipt(result: result)
            } else {
                receipt = .failed("Could not save URL")
            }
            postToast(
                message: receipt.toastMessage(success: "Saved from Services"),
                isSuccess: receipt.isSuccess
            )
            return
        }

        // Plain text → new note
        do {
            let result = try noteCaptureHandler(trimmed)
            let receipt = CaptureReceipt(result: result)
            postToast(
                message: receipt.toastMessage(success: "Created note from Services"),
                isSuccess: receipt.isSuccess
            )
        } catch {
            postToast(message: "Could not create note from Services", isSuccess: false)
        }
    }

    // MARK: - Image Service (public.png / public.jpeg / public.tiff)

    @objc nonisolated func sendImageToCider(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let imageData = pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            ?? pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff)
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
        Task { @MainActor [weak self] in
            self?.handleImage(imageData)
        }
    }

    func handleImage(_ data: Data?) {
        guard let data else { return }
        do {
            let result = try imageCaptureHandler(data, nil, nil)
            let receipt = CaptureReceipt(result: result)
            postToast(
                message: receipt.toastMessage(success: "Saved image from Services"),
                isSuccess: receipt.isSuccess
            )
        } catch {
            postToast(message: "Could not save image from Services", isSuccess: false)
        }
    }

    // MARK: - Toast

    private func postToast(message: String, isSuccess: Bool) {
        toastHandler(message, isSuccess)
    }
}
