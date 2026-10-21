import Foundation
import StrandImport
import WhoopStore

// Print aggregate counts only. No user-supplied health file belongs in git or CI artifacts.
@main enum ImportProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a WHOOP ZIP or folder") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let parsed = try WhoopExportImporter().import(from: url)
        let store = try await WhoopStore.inMemory()
        let source = "whoop-import-probe", other = "other-source-probe"
        try await store.upsertDevice(id: source, mac: nil, name: nil)
        try await store.upsertDevice(id: other, mac: nil, name: nil)
        _ = try await store.upsertMetricSeries([MetricPoint(day: "2026-10-05", key: "hrv", value: 999)], deviceId: other)
        _ = try await WhoopImporter.importExport(url: url, into: store, deviceId: source)
        let first = try await counts(store, source)
        _ = try await WhoopImporter.importExport(url: url, into: store, deviceId: source)
        let second = try await counts(store, source)
        precondition(first == second, "Reimport duplicated records")
        let untouched = try await store.metricSeries(deviceId: other, key: "hrv", from: "1900-01-01", to: "2200-01-01")
        precondition(untouched.count == 1 && untouched[0].value == 999, "Cross-source overwrite")
        var expectedByDay: [String: WhoopCycleRow] = [:]
        for cycle in parsed.cycles {
            if let day = WhoopDayKeying.wakeDayKey(wake: cycle.wakeOnset, end: cycle.cycleEnd,
                                                  start: cycle.cycleStart, tzOffsetMin: cycle.tzOffsetMin) {
                expectedByDay[day] = cycle
            }
        }
        precondition(first["days"] == expectedByDay.count)
        precondition(first["workouts"] == parsed.workouts.filter { $0.workoutStart != nil && $0.workoutEnd != nil }.count)
        let metrics = try await store.dailyMetrics(deviceId: source, from: "1900-01-01", to: "2200-01-01")
        for (day, cycle) in expectedByDay {
            guard let stored = metrics.first(where: { $0.day == day }) else { preconditionFailure("Missing day") }
            precondition(stored.strain == WhoopExportImporter.effortFromImportedDayStrain(cycle.dayStrain))
            precondition(stored.efficiency == WhoopExportImporter.fractionFromImportedEfficiencyPct(cycle.sleepEfficiencyPct))
        }
        let result: [String: Any] = ["parsed": parsed.summary.countsByCategory, "persisted": first,
                                   "reimport_idempotent": true, "other_source_preserved": true,
                                   "strain_and_efficiency_normalized": true,
                                   "parsed_naps": parsed.sleeps.filter(\.isNap).count,
                                   "cycles_sharing_wake_day": parsed.cycles.count - expectedByDay.count,
                                   "skipped_spans": parsed.summary.skippedSpans]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }

    static func counts(_ store: WhoopStore, _ source: String) async throws -> [String: Int] {
        let days = try await store.dailyMetrics(deviceId: source, from: "1900-01-01", to: "2200-01-01")
        let sleeps = try await store.sleepSessions(deviceId: source, from: 0, to: 7_000_000_000, limit: 1_000_000)
        let workouts = try await store.workouts(deviceId: source, from: 0, to: 7_000_000_000, limit: 1_000_000)
        let journal = try await store.journalEntries(deviceId: source, from: "1900-01-01", to: "2200-01-01")
        return ["days": days.count, "sleeps": sleeps.count, "workouts": workouts.count, "journal": journal.count]
    }
}
