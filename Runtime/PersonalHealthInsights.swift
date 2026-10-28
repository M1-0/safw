#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import StrandDesign
import SafwResearch
import WhoopStore

struct PersonalHealthInsightsShortcut: View {
    var body: some View {
        NavigationLink { PersonalHealthInsightsView() } label: {
            NoopCard {
                HStack(spacing: NoopMetrics.cardInnerSpacing) {
                    Image(systemName: "waveform.path.ecg").font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.accent)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Signal quality").font(StrandFont.headline)
                        Text("Coverage and gaps in recorded sleep data")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }
}

struct PersonalHealthInsightsView: View {
    @EnvironmentObject private var repo: Repository
    @State private var report: PersonalSignalCoverage.Report?
    @State private var night: CachedSleepSession?
    @State private var sourceID = ""
    @State private var failed = false
    @State private var loading = false
    @State private var generation = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                        Text("Last recorded sleep signal").font(StrandFont.headline)
                        if loading { ProgressView() }
                        if sourceID == repo.deviceId, let report, let night {
                            Text(Date(timeIntervalSince1970: Double(night.endTs)), style: .date)
                                .font(StrandFont.subhead)
                            LabeledContent("Measured HR coverage", value: report.fraction.formatted(.percent.precision(.fractionLength(0))))
                            LabeledContent("Longest HR gap", value: Duration.seconds(report.longestGapSeconds).formatted(.time(pattern: .hourMinuteSecond)))
                            LabeledContent("Conflicting seconds", value: report.conflictingSeconds.formatted())
                            if night.stagingSparse == true {
                                Text("Sleep staging has sparse motion data.")
                                    .foregroundStyle(StrandPalette.metricAmber)
                            }
                            Text("Only measured heart-rate seconds from the selected strap are counted. Imported scores and optical estimates do not fill gaps.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        } else if !loading {
                            Text(failed ? String(localized: "Could not read sleep signal history.") : String(localized: "No completed sleep with signal history in the last seven days."))
                                .font(StrandFont.subhead)
                        }
                        Text("Coverage describes available data, not sleep-stage accuracy. High coverage does not validate REM, deep sleep, or recovery.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }.padding(NoopMetrics.cardPadding)
        }
        .navigationTitle("Signal quality")
        .task(id: "\(repo.deviceId)|\(repo.refreshSeq)") { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor private func refresh() async {
        generation += 1
        let request = generation
        let source = repo.deviceId
        sourceID = source; report = nil; night = nil; failed = false; loading = true
        defer { if generation == request { loading = false } }
        guard let store = await repo.storeHandle() else {
            if generation == request { failed = true }
            return
        }
        do {
            let now = Int(Date().timeIntervalSince1970)
            let computed = try await store.sleepSessions(deviceId: source + "-noop", from: now - 7 * 86_400, to: now, limit: 100)
            let imported = try await store.sleepSessions(deviceId: source, from: now - 7 * 86_400, to: now, limit: 100)
            let candidates = (computed + imported).filter { $0.endTs <= now && $0.endTs > $0.effectiveStartTs }
            guard let latest = candidates.max(by: { $0.endTs < $1.endTs }) else { return }
            let samples = try await PersonalMinuteStore(store: store).personalMeasuredHR(
                deviceID: source, from: latest.effectiveStartTs, to: latest.endTs)
            let result = await runUnescalated(priority: .utility) {
                PersonalSignalCoverage.analyze(samples, from: latest.effectiveStartTs, to: latest.endTs)
            }
            guard !Task.isCancelled, generation == request, repo.deviceId == source, sourceID == source else { return }
            report = result; night = latest
        } catch {
            guard !Task.isCancelled, generation == request, repo.deviceId == source else { return }
            failed = true; report = nil; night = nil
        }
    }
}
#endif
