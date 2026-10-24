"""Build 440: data-quality fixes and read-only iOS health surfaces."""
import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent


def apply(root, replace, catalog_keys):
    for name in ["PersonalSignalCoverageTests.swift", "PersonalGlucoseHistoryTests.swift"]:
        shutil.copy2(HERE / "Tests" / name, root / "Personal/Research/Tests/SafwResearchTests" / name)
    shutil.copy2(HERE / "Tests/PersonalRecoveryValidityTests.swift",
                 root / "Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalRecoveryValidityTests.swift")

    scorer = "Packages/StrandAnalytics/Sources/StrandAnalytics/RecoveryScorer.swift"
    replace(root, scorer, "        guard let hrvB = hrvBaseline else { return nil }", """        guard let hrvB = hrvBaseline else { return nil }

        // Safw: malformed imported/computed values must not become a reassuring clamped
        // score. Validate only terms that actually participate; retain the existing formula
        // and all finite valid-input results. Zero baseline spread is allowed upstream.
        func validBaseline(_ b: DriverBaseline) -> Bool {
            b.mean.isFinite && b.spread.isFinite && b.spread >= 0
        }
        guard hrv.isFinite, hrv > 0, validBaseline(hrvB) else { return nil }
        if let b = rhrBaseline {
            guard rhr.isFinite, rhr > 0, validBaseline(b) else { return nil }
        }
        if let value = resp, let b = respBaseline {
            guard value.isFinite, value > 0, validBaseline(b) else { return nil }
        }
        if let value = sleepPerf {
            guard value.isFinite, (0...1).contains(value) else { return nil }
        }
        if let value = skinTempDev, !value.isFinite { return nil }
        if let value = recoveryIndexSlope, !value.isFinite { return nil }
        if let value = priorDayEffort, let b = effortBaseline {
            guard value.isFinite, (0...100).contains(value), validBaseline(b) else { return nil }
        }""", 1)
    replace(root, scorer, "        return logisticScore(compositeZ: z)",
            "        guard z.isFinite else { return nil }\n        return logisticScore(compositeZ: z)", 1)
    replace(root, "Packages/StrandAnalytics/Sources/StrandAnalytics/RecoveryScorer+Trace.swift",
            "        // Per-driver baseline state lines (mean / spread / nValid / status).", """        guard score != nil else {
            lines.append("charge nilScore reason=invalidInput")
            return (score, lines)
        }

        // Per-driver baseline state lines (mean / spread / nValid / status).""", 1)

    replace(root, "Strand/Liquid/LiquidTodayView.swift", "                        PersonalValidationShortcut()",
            "                        PersonalValidationShortcut()\n                        PersonalHealthInsightsShortcut()", 1)
    replace(root, "Strand/Screens/DataSourcesView.swift", "                PersonalValidationShortcut()",
            "                PersonalValidationShortcut()\n                PersonalHealthInsightsShortcut()", 1)
    main = root / "Strand/Resources/Localizable.xcstrings"
    extras = json.loads((HERE / "Audit/health-440-ar.json").read_text())
    main.write_text(catalog_keys(main.read_text(), extras.keys()))
