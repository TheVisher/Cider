import Foundation

enum DashboardSecondBrainAuthority: String, Codable, Sendable {
    case uiPreferenceState = "ui_preference_state"
}

struct DashboardSecondBrainContract: Hashable, Codable, Sendable {
    var authority: DashboardSecondBrainAuthority
    var isSecondBrainTruth: Bool
    var homePrimaryReadModel: String
    var safeGraphCommands: [String]

    static let uiPreferenceState = DashboardSecondBrainContract(
        authority: .uiPreferenceState,
        isSecondBrainTruth: false,
        homePrimaryReadModel: "HomeOverviewDataProvider",
        safeGraphCommands: ["cider-cli item graph-health --json"]
    )
}

extension DashboardTopic {
    var secondBrainContract: DashboardSecondBrainContract {
        .uiPreferenceState
    }
}

extension DashboardCard {
    var secondBrainContract: DashboardSecondBrainContract {
        .uiPreferenceState
    }

    var secondBrainOwnerRef: SecondBrainOwnerRef? {
        nil
    }
}

