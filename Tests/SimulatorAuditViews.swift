#if DEBUG && MYNOOP_PERSONAL && os(iOS)
import SwiftUI
import StrandDesign

// QA-only hosts for existing screens and synthetic empty/zero/half/full vessels.
// Copied into the app exclusively by the separate simulator workflow.
struct PersonalWaterAuditView: View {
    var body: some View {
        VStack(spacing: NoopMetrics.sectionSpacing) {
            HStack(spacing: NoopMetrics.gap) {
                LiquidScoreGauge(score: nil, tint: StrandPalette.chargeColor, diameter: 140, animated: false)
                LiquidScoreGauge(score: 0, tint: StrandPalette.effortColor, diameter: 140, animated: false)
            }
            HStack(spacing: NoopMetrics.gap) {
                LiquidScoreGauge(score: 50, tint: StrandPalette.restColor, diameter: 140, animated: false)
                LiquidScoreGauge(score: 100, tint: StrandPalette.chargeColor, diameter: 140, animated: false)
            }
        }
    }
}

struct PersonalCustomizationAuditView: View {
    let destination: TodayCustomizationDestination
    @State private var sections = ""
    @State private var hidden = ""
    @State private var metrics = ""
    @State private var detailed = false
    @State private var days = 7
    @State private var dashboard = ""
    @State private var hosted = ""
    var body: some View {
        TodayCustomizationSheet(initialDestination: destination,
            sectionOrderRaw: $sections, hiddenSectionsRaw: $hidden, keyMetricsRaw: $metrics,
            keyMetricsDetailed: $detailed, keyMetricsWindowDays: $days,
            dashboardCardsRaw: $dashboard, hostedCardsRaw: $hosted)
    }
}
#endif
