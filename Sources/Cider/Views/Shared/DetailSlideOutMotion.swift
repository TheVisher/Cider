import SwiftUI

enum DetailSlideOutChildTransitionStyle: Equatable {
    case identity
}

enum DetailSlideOutMotionPolicy {
    static func sidebarTransitionStyle() -> DetailSlideOutChildTransitionStyle {
        .identity
    }

    static func preloadDelay(for detailViewMode: DetailViewMode) -> Duration {
        switch detailViewMode {
        case .slideOut:
            // Let the entrance animation finish before booting WKWebView work.
            return .milliseconds(700)
        case .page, .fullPanel:
            return .zero
        }
    }

    static func shouldCompositeSurface(detailViewMode: DetailViewMode) -> Bool {
        switch detailViewMode {
        case .slideOut, .page, .fullPanel:
            return true
        }
    }
}

extension AnyTransition {
    static func detailSlideOutSidebar(style: DetailSlideOutChildTransitionStyle) -> AnyTransition {
        switch style {
        case .identity:
            return .identity
        }
    }
}

@MainActor
enum DetailHeroPreviewImageBootstrap {
    static func cachedThumbnailImage(filePath: String?, modifiedAt: TimeInterval) -> NSImage? {
        guard let filePath else { return nil }
        return BookmarkThumbnailCache.shared.get(filePath, modifiedAt: modifiedAt)?.image
    }
}
