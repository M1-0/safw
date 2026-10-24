#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import Charts
import HealthKit
import StrandDesign
import SafwResearch

@MainActor final class PersonalGlucoseReader: ObservableObject {
    static let preference = "personal.glucoseHistory"
    @Published private(set) var readings: [PersonalGlucoseHistory.Reading] = []
    @Published private(set) var busy = false
    @Published private(set) var message = "Glucose access is off."
    private let store = HKHealthStore()
    private var generation = 0
    static let mgDL = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    static let mmolL = HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())

    private func available() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Apple Health is unavailable on this device."; return false
        }
        guard HealthKitBridge.hasHealthKitEntitlement else {
            message = "This signed build cannot access Apple Health. A HealthKit-enabled signing profile is required."; return false
        }
        return true
    }

    func authorize() async -> Bool {
        guard !busy, available(), let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return false }
        busy = true
        defer { busy = false }
        do {
            // No write scope, no other health types, no connection to validation exports.
            try await store.requestAuthorization(toShare: [], read: [type])
            return true // Permission dialog completed; read permission is deliberately unknowable.
        } catch {
            message = "Could not request Apple Health access."; return false
        }
    }

    func clear() {
        generation += 1
        readings = []
        message = "Glucose access is off."
    }

    func refresh() async {
        guard !busy, UserDefaults.standard.bool(forKey: Self.preference), available(),
              let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return }
        busy = true
        generation += 1
        let request = generation
        readings = [] // A failed/revoked query must not retain an apparently current record.
        message = "Loading glucose history…"
        defer { busy = false }
        let now = Date()
        let from = now.addingTimeInterval(-7 * 86_400)
        let unit = Self.mgDL
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now, options: .strictStartDate)
        do {
            let rows: [PersonalGlucoseHistory.Reading] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    let rows = (samples as? [HKQuantitySample] ?? []).map { sample in
                        PersonalGlucoseHistory.Reading(id: sample.uuid.uuidString,
                            timestamp: sample.startDate.timeIntervalSince1970,
                            mgDL: sample.quantity.doubleValue(for: unit),
                            sourceID: sample.sourceRevision.source.bundleIdentifier,
                            sourceName: sample.sourceRevision.source.name,
                            manuallyEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true)
                    }
                    continuation.resume(returning: rows)
                }
                store.execute(query)
            }
            guard generation == request, UserDefaults.standard.bool(forKey: Self.preference) else { return }
            readings = PersonalGlucoseHistory.normalized(rows, from: from.timeIntervalSince1970, through: now.timeIntervalSince1970)
            message = readings.isEmpty ? "No glucose readings are available. There may be no data or read access may not be granted." : "Recorded readings from the last seven days"
        } catch {
            guard generation == request else { return }
            readings = []
            message = "Could not read glucose history. Refresh after checking Apple Health access."
        }
    }
}

struct PersonalGlucoseView: View {
    @StateObject private var reader = PersonalGlucoseReader()
    @AppStorage(PersonalGlucoseReader.preference) private var enabled = false
    @Environment(\.scenePhase) private var phase
    @State private var useMmol = false
    private var unitLabel: String { useMmol ? "mmol/L" : "mg/dL" }
    private var displayed: [PersonalGlucoseHistory.Reading] { enabled ? reader.readings : [] }
    private func value(_ row: PersonalGlucoseHistory.Reading) -> Double {
        HKQuantity(unit: PersonalGlucoseReader.mgDL, doubleValue: row.mgDL)
            .doubleValue(for: useMmol ? PersonalGlucoseReader.mmolL : PersonalGlucoseReader.mgDL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                        Text("Blood glucose history").font(StrandFont.headline)
                        Text("Safw displays readings already saved in Apple Health. WHOOP does not supply glucose readings, and Safw does not infer diabetes risk from heart rate.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        Text(LocalizedStringKey(reader.message)).font(StrandFont.footnote)
                        if reader.busy { ProgressView() }
                        if enabled {
                            Button("Refresh glucose history") { Task { await reader.refresh() } }.disabled(reader.busy)
                            Button("Disconnect glucose view") { enabled = false; reader.clear() }
                        } else {
                            Button("Connect Apple Health glucose") {
                                Task { if await reader.authorize() { enabled = true } }
                            }.disabled(reader.busy)
                        }
                        Text("This view is not a live monitor or an alarm. Readings may be delayed. Use the original glucose device or app for treatment decisions.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if let latest = displayed.last {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                            Text("Latest recorded reading").font(StrandFont.headline)
                            Picker("Glucose unit", selection: $useMmol) {
                                Text(verbatim: "mg/dL").tag(false)
                                Text(verbatim: "mmol/L").tag(true)
                            }.pickerStyle(.segmented)
                            Text("\(value(latest).formatted(.number.precision(.fractionLength(useMmol ? 1 : 0)))) \(unitLabel)")
                                .font(StrandFont.title1).environment(\.layoutDirection, .leftToRight)
                            provenance(latest)
                            // Discrete points: never interpolate through missing time or combine sources.
                            Chart(displayed) { row in
                                PointMark(x: .value("Time", Date(timeIntervalSince1970: row.timestamp)),
                                          y: .value(unitLabel, value(row)))
                                    .foregroundStyle(by: .value("Source", row.sourceName + " · " + row.sourceID))
                            }
                            .frame(height: 200).environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                            Text("Recent recorded readings").font(StrandFont.headline)
                            ForEach(Array(displayed.suffix(20).reversed())) { row in
                                HStack(alignment: .top, spacing: NoopMetrics.gap) {
                                    provenance(row)
                                    Spacer(minLength: 0)
                                    Text("\(value(row).formatted(.number.precision(.fractionLength(useMmol ? 1 : 0)))) \(unitLabel)")
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                            }
                        }
                    }
                }
            }.padding(NoopMetrics.cardPadding)
        }
        .navigationTitle("Blood glucose history")
        .task(id: "\(enabled)|\(phase == .active)") {
            if enabled && phase == .active { await reader.refresh() }
            if !enabled { reader.clear() }
        }
        .refreshable { if enabled { await reader.refresh() } }
    }

    private func provenance(_ row: PersonalGlucoseHistory.Reading) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(Date(timeIntervalSince1970: row.timestamp).formatted(date: .abbreviated, time: .shortened))
            Text(verbatim: row.sourceName).foregroundStyle(StrandPalette.textSecondary)
            if row.manuallyEntered { Text("Entered manually in Apple Health") }
        }.font(StrandFont.footnote)
    }
}
#endif
