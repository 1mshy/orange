import AppKit

enum SoundPlayer {
    private static let tick = NSSound(named: NSSound.Name("Tink"))
    private static let done = NSSound(named: NSSound.Name("Glass"))
    @MainActor static func highlight() {
        guard AppSettings.shared.soundsEnabled else { return }
        tick?.stop(); tick?.volume = 0.25; tick?.play()
    }
    @MainActor static func completed() {
        guard AppSettings.shared.soundsEnabled else { return }
        done?.volume = 0.5; done?.play()
    }
}
