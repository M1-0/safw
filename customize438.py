"""Additive Safw 438 surfaces; exact seams keep upstream updates reviewable."""
import json
import re
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent

def apply(root, replace, catalog_keys):
    research = root / "Personal/Research"
    sources = research / "Sources/SafwResearch"
    tests = research / "Tests/SafwResearchTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for module in ["Analytics", "Store"]:
        for source in (HERE / "Modules" / module).glob("*.swift"):
            shutil.copy2(source, sources / source.name)
    for name in ["PersonalMinuteStressTests.swift", "PersonalMinuteStoreTests.swift"]:
        shutil.copy2(HERE / "Tests" / name, tests / name)
    shutil.copy2(HERE / "Modules/Package.swift", research / "Package.swift")

    replace(root, 'StrandiOS/App/RootTabView.swift', '        .tint(StrandPalette.accent)\n', '        .tint(StrandPalette.accent)\n        #if MYNOOP_PERSONAL\n        .background(PersonalMinuteRecordingTask())\n        #endif\n', 1)
    replace(root, 'Strand/Liquid/LiquidTodayView.swift', '                    ActiveWorkoutIndicatorSection(showStart: selectedDayOffset == 0)', '                    ActiveWorkoutIndicatorSection(showStart: selectedDayOffset == 0)\n                    #if MYNOOP_PERSONAL\n                    if selectedDayOffset == 0 { PersonalStressShortcut() }\n                    #endif', 1)
    # Use a whole Arabic word, not individually spaced letters (Arabic shaping needs the run).
    replace(root, 'Strand/Liquid/LiquidTodayView.swift', '''        HStack(spacing: 14) {
            ForEach(Array("NOOP".enumerated()), id: \\.offset) { _, ch in
                Text(String(ch))
                    .font(StrandFont.rounded(16, weight: .bold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }''', '''        Group {
            #if MYNOOP_PERSONAL
            Text(verbatim: "صفو")
                .font(StrandFont.title2.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            #else
            HStack(spacing: 14) {
                ForEach(Array("NOOP".enumerated()), id: \\.offset) { _, ch in
                    Text(String(ch))
                        .font(StrandFont.rounded(16, weight: .bold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            #endif
        }''', 1)
    replace(root, 'Strand/Screens/StressView.swift', '''                ComingSoon(what: "Reading your heart-rate variability and resting heart rate…")''', '''                #if MYNOOP_PERSONAL
                PersonalStressEmpty()
                PersonalMinuteResearchSection()
                #else
                ComingSoon(what: "Reading your heart-rate variability and resting heart rate…")
                #endif''', 1)
    replace(root, 'Strand/Screens/StressView.swift', '''        ComingSoon(what: "No stress history yet. Import your WHOOP export in Data Sources to see it.")''', '''        #if MYNOOP_PERSONAL
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            PersonalStressEmpty()
            PersonalMinuteResearchSection()
            if let daytime, !daytime.scored.isEmpty { daytimeSection(daytime) }
        }
        #else
        ComingSoon(what: "No stress history yet. Import your WHOOP export in Data Sources to see it.")
        #endif''', 1)
    replace(root, 'Strand/Screens/StressView.swift', '''            heroCard(model)
                .staggeredAppear(index: 0)''', '''            heroCard(model)
                .staggeredAppear(index: 0)
            #if MYNOOP_PERSONAL
            PersonalMinuteResearchSection()
            #endif''', 1)
    replace(root, 'Strand/Screens/StressView.swift', '    let score: Double            // 0–3 (today)', '    let scoredDay: String\n    let score: Double            // 0–3 (today)', 1)
    replace(root, 'Strand/Screens/StressView.swift', '        let today = days[idx]', '        let today = days[idx]\n        self.scoredDay = today.day', 1)
    replace(root, 'Strand/Screens/StressView.swift', '''                        // One plain-English line beside the gauge.
                        Text(model.explanation)''', '''                        #if MYNOOP_PERSONAL
                        Text("Daily estimate from \\(model.scoredDay)")
                            .font(StrandFont.footnote)
                        Text("A daily estimate, not a live reading")
                            .font(StrandFont.footnote)
                        #endif
                        // One plain-English line beside the gauge.
                        Text(model.explanation)''', 1)
    for old, new in [('chevron.left','chevron.backward'),('chevron.right','chevron.forward')]:
        replace(root, 'Strand/Screens/FullDayChartView.swift', f'systemName: "{old}"', f'systemName: "{new}"')
    replace(root, 'Strand/Data/Units.swift', 'self == .bar ? "Bars" : "Line"', 'self == .bar ? String(localized: "Bars") : String(localized: "Line")', 1)
    replace(root, 'Strand/Data/Units.swift', 'self == .deep ? "Deep sleep" : "Whole night"', 'self == .deep ? String(localized: "Deep sleep") : String(localized: "Whole night")', 1)
    replace(root, 'Strand/Screens/BreathingView.swift', 'String(format: "%.1f br/min",', 'String(format: String(localized: "%.1f br/min"),', 1)
    # Conditional strings otherwise select Text<String>, bypassing the catalog at runtime.
    for path, old, new in [
        ('StorageView', 'Text(cleaning ? "Cleaning up…" : "Clean up now")', 'Text(cleaning ? String(localized: "Cleaning up…") : String(localized: "Clean up now"))'),
        ('ManualWorkoutSheet', 'Text(editing == nil ? "Add Workout" : "Edit Workout")', 'Text(editing == nil ? String(localized: "Add Workout") : String(localized: "Edit Workout"))'),
        ('CompareView', 'Text(selected.count >= maxSelection ? "Max 4" : "Add metric")', 'Text(selected.count >= maxSelection ? String(localized: "Max 4") : String(localized: "Add metric"))'),
        ('CompareView', 'Text(d == 0 ? "low" : d == 1 ? "high" : "mid")', 'Text(d == 0 ? String(localized: "low") : d == 1 ? String(localized: "high") : String(localized: "mid"))'),
        ('SleepView', 'Text(napSuffix ? "About this nap" : "About your main sleep")', 'Text(napSuffix ? String(localized: "About this nap") : String(localized: "About your main sleep"))'),
        ('LiveWorkoutView', 'Text(paused ? "Resume" : "Pause")', 'Text(paused ? String(localized: "Resume") : String(localized: "Pause"))'),
        ('WorkoutDetailView', 'Text(effortScale == .whoop ? "of 21" : "of 100")', 'Text(effortScale == .whoop ? String(localized: "of 21") : String(localized: "of 100"))'),
        ('WorkoutsView', 'Text(effortScale == .whoop ? "of 21" : "of 100")', 'Text(effortScale == .whoop ? String(localized: "of 21") : String(localized: "of 100"))'),
        ('WorkoutsView', 'Text(grid.streak == 1 ? "day in a row" : "days in a row")', 'Text(grid.streak == 1 ? String(localized: "day in a row") : String(localized: "days in a row"))'),
        ('BackupSyncView', 'Text(lastMs > 0 ? "Last backup: \\(relativeTime(lastMs))" : "No backup yet.")', 'Text(lastMs > 0 ? String(localized: "Last backup: \\(relativeTime(lastMs))") : String(localized: "No backup yet."))'),
        ('LiveWorkoutView', 'Text(zone >= 1 ? "Zone \\(zone) · \\(Self.zoneName(zone))" : "Below Zone 1")', 'Text(zone >= 1 ? String(localized: "Zone \\(zone) · \\(Self.zoneName(zone))") : String(localized: "Below Zone 1"))'),
        ('StressView', '? "Today\'s value is your recorded daily stress score (0-3)."\n                     : "Stress is derived from two autonomic signals."', '? String(localized: "Today\'s value is your recorded daily stress score (0-3).")\n                     : String(localized: "Stress is derived from two autonomic signals.")'),
    ]:
        replace(root, f'Strand/Screens/{path}.swift', old, new, 1)
    replace(root, 'Strand/Screens/WorkoutDetailView.swift', '\\(effortScale == .whoop ? "of 21" : "of 100")', '\\(effortScale == .whoop ? String(localized: "of 21") : String(localized: "of 100"))', 1)
    replace(root, 'Strand/Screens/HRVSnapshotView.swift', 'Label(saved ? "Saved" : "Save", systemImage:', 'Label(saved ? String(localized: "Saved") : String(localized: "Save"), systemImage:', 1)
    # A first Latin letter works for English; slicing Arabic day names yields repeated alifs.
    replace(root, 'Strand/Screens/HydrationView.swift', 'return String(Self.weekdayAbbrev.string(from: date).prefix(1))', 'return date.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.activeLocale))', 1)
    # Package strings require their own catalog; adding them only to Bundle.main is ineffective.
    design = root / 'Packages/StrandDesign/Sources/StrandDesign/Resources/Localizable.xcstrings'
    appearance = (root / 'Packages/StrandDesign/Sources/StrandDesign/Appearance.swift').read_text()
    design.write_text(catalog_keys(design.read_text(), re.findall(r'localized: "([^"\n]+)"', appearance)))
    main = root / 'Strand/Resources/Localizable.xcstrings'
    extras = json.loads((HERE / 'Audit/extra-438-ar.json').read_text())
    main.write_text(catalog_keys(main.read_text(), extras.keys()))
    # Original upstream notices are not renamed or rewritten. The personal product gets its own mark.
    shutil.copy2(HERE / 'Brand/icon_1024.png', root / 'StrandiOS/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png')
    replace(root, 'StrandiOS/App/RootTabView.swift', 'Text(title).strandOverline()', 'Text(LocalizedStringKey(title)).strandOverline()', 1)
    replace(root, 'StrandiOS/App/RootTabView.swift', '.accessibilityLabel(Text(title))', '.accessibilityLabel(Text(LocalizedStringKey(title)))', 1)
    replace(root, 'StrandiOS/App/RootTabView.swift', '.degrees(isOpen ? 0 : -90)', '.degrees(isOpen ? 0 : (AppLanguage.isRightToLeft ? 90 : -90))', 1)
    replace(root, 'Strand/Screens/SettingsView.swift', '.degrees(isExpanded ? 0 : -90)', '.degrees(isExpanded ? 0 : (AppLanguage.isRightToLeft ? 90 : -90))', 1)
    replace(root, 'Strand/Screens/SettingsView.swift', 'Text("NOOP")', 'Text(verbatim: "صفو")\n                    Text("Built on NOOP").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)', 1)
    replace(root, 'StrandiOSWidgets/NOOPWidget.swift', 'Text("NOOP")', 'Text(verbatim: "صفو")', 1)
    replace(root, 'StrandiOSWidgets/NOOPWidget.swift', '.configurationDisplayName("NOOP")', '.configurationDisplayName("صفو")', 1)
    replace(root, 'Strand/Screens/TrendsReportView.swift', 'Text("NOOP").font(StrandFont.overline).tracking(StrandFont.overlineTracking)', 'Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "NOOP").font(StrandFont.overline).tracking(AppLanguage.isRightToLeft ? 0 : StrandFont.overlineTracking)', 1)
    # The shared overline helper must not add tracking between connected Arabic glyphs.
    typography = 'Packages/StrandDesign/Sources/StrandDesign/Typography.swift'
    replace(root, typography, '''        self.font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)''', '''        self.modifier(PersonalLocalizedOverline())''', 1)
    p = root / typography
    p.write_text(p.read_text() + '''
private struct PersonalLocalizedOverline: ViewModifier {
    @Environment(\\.layoutDirection) private var direction
    func body(content: Content) -> some View {
        content.font(StrandFont.overline)
            .tracking(direction == .rightToLeft ? 0 : StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)
    }
}
''')
    replace(root, 'Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift', '''            // Provenance also references the physical/import source separately from its computed''', '''            if try db.tableExists("personalStressMinute") {
                try db.execute(sql: "DELETE FROM personalStressMinute WHERE deviceId = ?", arguments: [deviceId])
            }
            // Provenance also references the physical/import source separately from its computed''', 1)
