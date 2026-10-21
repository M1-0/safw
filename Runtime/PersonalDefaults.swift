import Foundation

enum PersonalDefaults {
    static func seed(defaults: UserDefaults = .standard) {
        if defaults.string(forKey: AppLanguage.storageKey) == nil {
            defaults.set("ar", forKey: AppLanguage.storageKey)
            AppLanguage.apply("ar", defaults: defaults)
        }
        for (key, value) in ["updates.autoCheck": false, "noop.coachEnabled": false,
                             "noop.liquidTodayEnabled": true] {
            if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
    }
}
