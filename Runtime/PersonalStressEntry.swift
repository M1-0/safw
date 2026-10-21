#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import StrandDesign

struct PersonalStressShortcut: View {
    var body: some View {
        NavigationLink(value: TabRoute.stress) {
            NoopCard(tint: StrandPalette.accent) {
                HStack(spacing: NoopMetrics.cardInnerSpacing) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(StrandFont.title2).foregroundStyle(StrandPalette.accent)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Stress monitor and timeline").font(StrandFont.headline)
                        Text("Daily estimate and recorded daytime history")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }
}

struct PersonalStressEmpty: View {
    var body: some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(spacing: NoopMetrics.cardInnerSpacing) {
                    PersonalStressGauge(score: nil, tint: StrandPalette.textTertiary)
                    Text("No reliable score yet").font(StrandFont.headline)
                }
                Text("Your stress monitor is here even before your first score. Sync heart-rate history or import your WHOOP history to build the daily estimate. Missing data is not zero stress.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                NavigationLink("Open Data Sources") { DataSourcesView() }
                NavigationLink("Open Live") { LiveView() }
            }
        }
    }
}
#endif
