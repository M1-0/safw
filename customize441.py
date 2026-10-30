"""Build 441: require personal baselines for optional recovery drivers."""
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent


def apply(root, replace, catalog_keys):
    shutil.copy2(HERE / "Tests/PersonalRecoveryBaselineTests.swift",
                 root / "Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalRecoveryBaselineTests.swift")
    scorer = "Packages/StrandAnalytics/Sources/StrandAnalytics/RecoveryScorer.swift"
    for name in ["resp", "effort"]:
        replace(root, scorer, f"{name}Baseline: {name}Baseline.map(DriverBaseline.init)",
                f"{name}Baseline: {name}Baseline.flatMap {{ $0.usable ? $0 : nil }}.map(DriverBaseline.init)", 1)

    # The driver rows and diagnostic trace read the baseline directly too. Normalize it
    # once at the same boundary, so they describe precisely the terms the score used.
    for file in ["ChargeDrivers.swift", "RecoveryScorer+Trace.swift"]:
        path = "Packages/StrandAnalytics/Sources/StrandAnalytics/" + file
        replace(root, path, "        let rhrB = rhrBaseline.flatMap { $0.usable ? $0 : nil }",
                "        let rhrB = rhrBaseline.flatMap { $0.usable ? $0 : nil }\n"
                "        let respB = respBaseline.flatMap { $0.usable ? $0 : nil }", 1)
        replace(root, path, "respBaseline: respBaseline,", "respBaseline: respB,")
        replace(root, path, "let b = respBaseline", "let b = respB")
