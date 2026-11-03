import Foundation
import MTCore

enum AppSettings {
    enum Keys {
        static let trimSilence = "trimSilence"
        static let minSilence = "minSilenceSeconds"
    }

    static var trimConfig: SilenceTrimConfig {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Keys.trimSilence) as? Bool ?? true
        let minSilence = defaults.object(forKey: Keys.minSilence) as? Double ?? 2.0
        return SilenceTrimConfig(minSilence: minSilence, enabled: enabled)
    }
}
