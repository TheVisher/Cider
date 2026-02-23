import AudioToolbox
import Foundation

enum CiderSoundEffect: String {
    case save = "Tink"
    case trash = "Funk"
    case clipboardReview = "Pop"

    nonisolated(unsafe) private static var soundIDs: [String: SystemSoundID] = [:]

    func play() {
        guard CiderConfig.load().enableSoundEffects else { return }

        if Self.soundIDs[rawValue] == nil {
            let url = URL(fileURLWithPath: "/System/Library/Sounds/\(rawValue).aiff")
            var id: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
            guard status == noErr else { return }
            Self.soundIDs[rawValue] = id
        }

        if let id = Self.soundIDs[rawValue] {
            AudioServicesPlaySystemSound(id)
        }
    }
}
