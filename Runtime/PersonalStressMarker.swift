#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import StrandDesign

// Keep the value and its comparison on separate lines so Arabic units stay readable.
struct PersonalStressMarker: View {
    let label: LocalizedStringKey
    let value: String
    let delta: String?
    let accent: Color
    let deltaColor: Color

    var body: some View {
        NoopCard(tint: accent) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text(label)
                    .font(StrandFont.overline)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(value)
                    .font(StrandFont.number(26))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let delta {
                    Text(delta)
                        .font(StrandFont.footnote)
                        .foregroundStyle(deltaColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.tileHeight, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
