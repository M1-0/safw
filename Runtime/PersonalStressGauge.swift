#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import StrandDesign

// Reuse the upstream dial and score. This is only a presentation customization.
struct PersonalStressGauge: View {
    let score: Double?
    let tint: Color

    var body: some View {
        let valid = score.flatMap { $0.isFinite ? $0 : nil }
        let fraction = valid.map { max(0, min(1, $0 / 3)) } ?? 0
        let number = valid.map(StressTrace.formatLevel) ?? "—"
        BevelGauge(fraction: fraction,
                   stops: [.init(color: tint.opacity(0.45), location: 0), .init(color: tint, location: 1)],
                   tipColor: tint, numberText: number,
                   captionText: String(localized: "of 3"), diameter: 104, lineWidth: 8,
                   animatedFraction: fraction)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(valid.map { String(localized: "Stress \(StressTrace.formatLevel($0)) of 3") } ?? String(localized: "Stress monitor unavailable"))
    }
}
#endif
