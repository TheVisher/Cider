import Foundation

struct DockManager {
    // TODO: Dock hiding and restoration will go here (v1.0 setup flow).
    func hideDock() {
        _ = Shell.run("defaults write com.apple.dock autohide -bool true")
        _ = Shell.run("defaults write com.apple.dock autohide-delay -float 1000")
        _ = Shell.run("defaults write com.apple.dock autohide-time-modifier -float 0")
        _ = Shell.run("killall Dock")
    }

    func restoreDock() {
        _ = Shell.run("defaults delete com.apple.dock autohide-delay")
        _ = Shell.run("defaults delete com.apple.dock autohide-time-modifier")
        _ = Shell.run("killall Dock")
    }
}
