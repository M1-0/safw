import Foundation

@main enum RuntimeChecks {
    static func main() {
        let suite = "mynoop-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let systemLanguages = defaults.stringArray(forKey: "AppleLanguages")
        PersonalDefaults.seed(defaults: defaults)
        precondition(defaults.string(forKey: AppLanguage.storageKey) == "ar")
        precondition(defaults.stringArray(forKey: "AppleLanguages") == ["ar"])
        precondition(defaults.bool(forKey: "noop.liquidTodayEnabled"))
        precondition(!defaults.bool(forKey: "noop.coachEnabled"))
        precondition(!defaults.bool(forKey: "updates.autoCheck"))
        defaults.set("en", forKey: AppLanguage.storageKey)
        AppLanguage.apply("en", defaults: defaults)
        defaults.set(true, forKey: "updates.autoCheck")
        PersonalDefaults.seed(defaults: defaults)
        precondition(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
        precondition(defaults.bool(forKey: "updates.autoCheck"))
        defaults.set("system", forKey: AppLanguage.storageKey)
        AppLanguage.apply("system", defaults: defaults)
        PersonalDefaults.seed(defaults: defaults)
        // On Apple platforms, UserDefaults inherits the global language after the local override
        // is removed. Verify the suite no longer overrides it and the inherited value is restored.
        precondition(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        precondition(defaults.stringArray(forKey: "AppleLanguages") == systemLanguages)
        for dx in [-200.0, -60, 0, 60, 200] {
            precondition(AppLanguage.navigationTranslation(dx, rightToLeft: false) == dx)
            precondition(AppLanguage.navigationTranslation(dx, rightToLeft: true) == -dx)
        }
        precondition(AppLanguage.resolve("ar").autonym == "العربية")
        print("PASS: Arabic first launch, privacy, liquid dashboard, saved choices, system language, RTL gestures")
    }
}
