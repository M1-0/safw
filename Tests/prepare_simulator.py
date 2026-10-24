"""Mount real screens in upstream's DEBUG-only harness; no user health data is used."""
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
here = Path(__file__).resolve().parent
p = root / 'StrandiOS/App/StrandiOSApp.swift'
s = p.read_text()
anchor = 'case "settings": return AnyView(SettingsView())'
assert s.count(anchor) == 1, 'Upstream debug-screen seam changed'
extra = '''
        case "datasources": return AnyView(DataSourcesView())
        case "validation": return AnyView(PersonalValidationView())
        case "healthinsights": return AnyView(PersonalHealthInsightsView())
        case "glucose": return AnyView(PersonalGlucoseView())
        case "onboarding": return AnyView(OnboardingWizard(onFinished: {}))
        case "waterstates": return AnyView(PersonalWaterAuditView())
        case "breathe": return AnyView(BreathingView())
        case "scoringguide": return AnyView(ScoringGuideView(onClose: {}))
        case "scoringcharge": return AnyView(ScoringGuideView(initialSection: .charge, onClose: {}))
        case "scoringeffort": return AnyView(ScoringGuideView(initialSection: .effort, onClose: {}))
        case "scoringrest": return AnyView(ScoringGuideView(initialSection: .rest, onClose: {}))
        case "deeptimeline": return AnyView(FullDayChartView())
        case "customizetoday": return AnyView(PersonalCustomizationAuditView(destination: .today))
        case "customizemetrics": return AnyView(PersonalCustomizationAuditView(destination: .keyMetrics))
        case "customizecards": return AnyView(PersonalCustomizationAuditView(destination: .yourCards))
        case "applehealth": return AnyView(AppleHealthView())
        case "storage": return AnyView(StorageView())
        case "backup": return AnyView(BackupSyncView())
        case "hydration": return AnyView(HydrationView())
        case "hrvsnapshot": return AnyView(HRVSnapshotView())
'''
p.write_text(s.replace(anchor, anchor + extra))
shutil.copy2(here / 'SimulatorAuditViews.swift', root / 'Personal/Runtime/SimulatorAuditViews.swift')
