import Foundation

struct NoteEditorImportProvenance: Equatable {
    enum SourceKind: String, Equatable {
        case textFile = "text_file"
        case imageFile = "image_file"
        case pasteboardImage = "pasteboard_image"
        case remoteImageURL = "remote_image_url"
        case webViewImage = "webview_image"
        case imagePicker = "image_picker"
    }

    let kind: SourceKind
    let filename: String?
    let sourceURL: URL?

    static func textFile(_ url: URL) -> NoteEditorImportProvenance {
        NoteEditorImportProvenance(kind: .textFile, filename: url.lastPathComponent, sourceURL: url)
    }

    static func imageFile(_ url: URL) -> NoteEditorImportProvenance {
        NoteEditorImportProvenance(kind: .imageFile, filename: url.lastPathComponent, sourceURL: url)
    }

    static func pasteboardImage(filename: String) -> NoteEditorImportProvenance {
        NoteEditorImportProvenance(kind: .pasteboardImage, filename: filename, sourceURL: nil)
    }

    static func remoteImageURL(_ url: URL, filename: String) -> NoteEditorImportProvenance {
        NoteEditorImportProvenance(kind: .remoteImageURL, filename: filename, sourceURL: url)
    }

    static func webViewImage(filename: String) -> NoteEditorImportProvenance {
        NoteEditorImportProvenance(kind: .webViewImage, filename: filename, sourceURL: nil)
    }

    static func imagePicker(_ url: URL) -> NoteEditorImportProvenance {
        NoteEditorImportProvenance(kind: .imagePicker, filename: url.lastPathComponent, sourceURL: url)
    }

    var auditMetadata: [String: String] {
        var metadata: [String: String] = ["importSource": kind.rawValue]
        if let filename, !filename.isEmpty {
            metadata["sourceFilename"] = filename
        }
        if let sourceURL {
            if sourceURL.isFileURL {
                metadata["sourcePath"] = sourceURL.path
            } else {
                metadata["sourceURL"] = sourceURL.absoluteString
            }
        }
        return metadata
    }
}
