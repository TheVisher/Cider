import AppKit
import SwiftUI

// MARK: - AI Assistant Panel

private enum AIAssistantFloatRequest {
    static let notificationName = Notification.Name.floatCiderSurface

    static func matches(_ notification: Notification) -> Bool {
        if matchesPayload(notification.object) {
            return true
        }

        return matchesPayload(notification.userInfo?["surface"])
            || matchesPayload(notification.userInfo?["ciderSurface"])
            || matchesPayload(notification.userInfo?["floatableSurface"])
    }

    private static func matchesPayload(_ payload: Any?) -> Bool {
        guard let payload else { return false }

        if let string = payload as? String {
            return normalized(string) == "aiassistant"
        }

        return normalized(String(describing: payload)) == "aiassistant"
    }

    private static func normalized(_ value: String) -> String {
        let lastComponent = value.split(separator: ".").last.map(String.init) ?? value
        return lastComponent
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}

extension AppDelegate {

    func startAIAssistantHotkeyDetection() {
        aiAssistantHotkeyDetector = AIAssistantHotkeyDetector()
        aiAssistantHotkeyDetector?.start()
    }

    func configureAIAssistantPanel() {
        aiAssistantPanel = nil
        aiAssistantShadowPanel = nil
        aiAssistantPanelFrameObservation = nil
    }

    func observeAIAssistantNotifications() {
        NotificationCenter.default.publisher(for: .toggleAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.floatingPanelManager?.isVisible(.aiAssistant) == true {
                    self.hideAIAssistantPanel()
                } else {
                    self.showAIAssistantPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.floatingPanelManager?.isVisible(.aiAssistant) != true {
                    self.showAIAssistantPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AIAssistantFloatRequest.notificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard AIAssistantFloatRequest.matches(notification) else { return }
                self?.showAIAssistantPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideAIAssistantPanel()
            }
            .store(in: &cancellables)
    }

    func showAIAssistantPanel() {
        floatingPanelManager?.float(.aiAssistant)
    }

    func hideAIAssistantPanel() {
        floatingPanelManager?.dock(.aiAssistant)
    }
}
