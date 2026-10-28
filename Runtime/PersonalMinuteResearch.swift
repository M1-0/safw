#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore
import SafwResearch

@MainActor final class PersonalMinuteRecorder: ObservableObject {
    static let shared = PersonalMinuteRecorder()
    static let preference = "personal.stressMinuteResearch"
    @Published private(set) var points: [PersonalMinuteStress.Point] = []
    @Published private(set) var deviceID: String?
    @Published private(set) var failed = false
    private var busy = false
    private var lastKey = ""

    func refresh(repo: Repository, force: Bool = false) async {
        let source = repo.deviceId
        if deviceID != source {
            points = []
            failed = false
            lastKey = ""
            deviceID = source
        }
        guard UserDefaults.standard.bool(forKey: Self.preference), !busy else { return }
        guard repo.activeStrapIsWhoop5() else { points = []; return }
        let now = Int(Date().timeIntervalSince1970)
        let key = "\(source)|\(now / 60)|\(repo.refreshSeq)"
        guard force || key != lastKey else { return }
        busy = true
        defer { busy = false }
        guard let store = await repo.storeHandle() else { failed = true; return }
        guard repo.deviceId == source, UserDefaults.standard.bool(forKey: Self.preference) else { return }
        let minutes = PersonalMinuteStore(store: store)
        do {
            let midnight = Calendar.current.startOfDay(for: Date())
            let start = Int(midnight.timeIntervalSince1970)
            let earlier = try await minutes.personalMinutes(deviceID: source, algorithm: PersonalMinuteStress.version,
                                                           from: start - PersonalMinuteStress.historySeconds, to: start)
            let history = try earlier.map { try JSONDecoder().decode(PersonalMinuteStress.Point.self, from: Data($0.payload.utf8)) }
            // One device and one measured stream: no Apple/import/PPG blending.
            let hr = try await minutes.personalMeasuredHR(deviceID: source, from: start - 300, to: now)
            let gravity = try await store.gravitySamples(deviceId: source,
                from: start - PersonalMinuteStress.warmup - PersonalMinuteStress.window - 1, to: now, limit: 200_000)
            // The imported-only repository API omits Bluetooth-computed nights. Exclude both
            // source partitions; a local night must never train the daytime baseline.
            let sleeps = try await minutes.personalSleepExclusions(deviceID: source,
                from: start - PersonalMinuteStress.historySeconds - PersonalMinuteStress.window, to: now)
            let workouts = await repo.workoutRows(days: 16)
            let excluded = sleeps
                + workouts.map { PersonalMinuteStress.Exclusion(start: $0.startTs, end: $0.endTs + 15 * 60) }
            let calculated = await runUnescalated(priority: .utility) {
                PersonalMinuteStress.analyze(hr: hr, gravity: gravity, from: start, to: now,
                    history: PersonalMinuteStress.references(history), excluding: excluded)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let rows = try calculated.map { p in
                PersonalMinuteRow(deviceID: source, end: p.end, algorithm: PersonalMinuteStress.version,
                                  payload: String(decoding: try encoder.encode(p), as: UTF8.self))
            }
            // A source switch while awaiting data must not flash the old device's score.
            guard repo.deviceId == source, UserDefaults.standard.bool(forKey: Self.preference) else { return }
            try await minutes.savePersonalMinutes(rows, batch: UUID().uuidString, now: now)
            guard repo.deviceId == source, UserDefaults.standard.bool(forKey: Self.preference) else { return }
            points = calculated
            failed = false
            lastKey = key
        } catch {
            guard repo.deviceId == source else { return }
            failed = true
            points = [] // Never hide a failed refresh behind a seemingly current cached value.
        }
    }
}

struct PersonalMinuteRecordingTask: View {
    @EnvironmentObject var repo: Repository
    @AppStorage(PersonalMinuteRecorder.preference) private var enabled = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: "\(enabled)|\(repo.deviceId)|\(repo.refreshSeq)") {
                if enabled { await PersonalMinuteRecorder.shared.refresh(repo: repo) }
            }
    }
}

struct PersonalMinuteResearchSection: View {
    @EnvironmentObject var repo: Repository
    @ObservedObject private var recorder = PersonalMinuteRecorder.shared
    @AppStorage(PersonalMinuteRecorder.preference) private var enabled = false
    @State private var showRows = false

    private var displayedPoints: [PersonalMinuteStress.Point] {
        recorder.deviceID == repo.deviceId ? recorder.points : []
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("Experimental minute research").font(StrandFont.headline)
                Toggle("Enable minute research", isOn: $enabled)
                Text("A five-minute signal window, evaluated once per minute. This experimental estimate is separate from NOOP's daily score and is not validated against WHOOP. Motion and missing data remain gaps.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                if enabled {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let current = PersonalMinuteStress.current(displayedPoints, now: Int(context.date.timeIntervalSince1970))
                        HStack(spacing: NoopMetrics.cardInnerSpacing) {
                            PersonalStressGauge(score: current?.level, tint: StrandPalette.accent)
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text(current.map { Self.reason($0.reason) } ?? String(localized: "Insufficient signal"))
                                    .font(StrandFont.headline)
                                if current?.level != nil { Text("Low confidence").font(StrandFont.footnote) }
                                if current?.level == nil {
                                    Text("The current minute has no reliable reading. The dial does not carry an older value forward.").font(StrandFont.footnote)
                                }
                                if let current, current.level != nil {
                                    Text("Coverage").font(StrandFont.footnote)
                                    Text(current.coverage.formatted(.percent.precision(.fractionLength(0))))
                                        .font(StrandFont.captionNumber)
                                }
                            }
                            .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    if displayedPoints.contains(where: { $0.level != nil }) {
                        minuteChart
                        HStack(spacing: NoopMetrics.gap) {
                            total("Calm", band: 0)
                            total("Moderate", band: 1)
                            total("High", band: 2)
                        }
                    } else {
                        Text("No minute readings yet. Leave the app connected and let history sync. This view uses recorded samples, not the number currently displayed on Live.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text("Heart-rate-only estimate; daytime wrist HRV is not used until its quality is validated.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    if recorder.failed && recorder.deviceID == repo.deviceId {
                        Text("Could not save the minute record. Try again after syncing.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.metricAmber)
                    }
                    Button("Reload minute history") { Task { await recorder.refresh(repo: repo, force: true) } }
                    DisclosureGroup("Minutes with readings", isExpanded: $showRows) {
                        LazyVStack(spacing: NoopMetrics.rowSpacing) {
                            ForEach(Array(displayedPoints.reversed()), id: \.end) { p in
                                HStack {
                                    Text(Date(timeIntervalSince1970: Double(p.end - 60)), style: .time)
                                    Spacer()
                                    Text(p.level.map(StressTrace.formatLevel) ?? Self.reason(p.reason))
                                        .multilineTextAlignment(.trailing)
                                }
                                .font(StrandFont.footnote)
                            }
                        }
                    }
                }
                Text("Research history is saved locally per device and algorithm version. Turning this off stops new calculations and keeps existing records.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .task(id: enabled) { if enabled { await recorder.refresh(repo: repo, force: true) } }
    }

    private struct PlotItem: Identifiable {
        let point: PersonalMinuteStress.Point
        let segment: Int
        var id: Int { point.end }
    }

    private var minuteChart: some View {
        // Explicit contiguous segment identity prevents a line crossing a missing/motion minute.
        let segments = displayedPoints.reduce(into: [PlotItem]()) { result, p in
            let previous = result.last
            let segment = (previous?.segment ?? 0) + ((p.level == nil || previous?.point.level == nil) ? 1 : 0)
            result.append(PlotItem(point: p, segment: segment))
        }
        return Chart(segments) { item in
            if let value = item.point.level {
                LineMark(x: .value(String(localized: "Time"), Date(timeIntervalSince1970: Double(item.point.end - 60))),
                         y: .value(String(localized: "Stress"), value), series: .value("Segment", item.segment))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        .chartYScale(domain: 0...3)
        .frame(height: 160)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func total(_ label: LocalizedStringKey, band: Int) -> some View {
        VStack(spacing: NoopMetrics.space1) {
            Text(label).font(StrandFont.footnote)
            Text("\(PersonalMinuteStress.minutes(displayedPoints, in: band)) min").font(StrandFont.captionNumber)
        }.frame(maxWidth: .infinity)
    }
    static func reason(_ value: PersonalMinuteStress.Reason) -> String {
        switch value {
        case .estimate: return String(localized: "Experimental estimate")
        case .insufficientSignal: return String(localized: "Insufficient signal")
        case .motionUnavailable: return String(localized: "Motion unavailable")
        case .activity: return String(localized: "Activity excluded")
        case .excluded: return String(localized: "Sleep or workout excluded")
        case .baselineUnavailable: return String(localized: "Baseline unavailable")
        }
    }
}
#endif
