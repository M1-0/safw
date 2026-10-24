import Foundation

/// Provenance-preserving display records, supplied only by the HealthKit adapter.
/// No HR/HRV/PPG input, glucose prediction, diagnostic thresholds, or treatment calculation.
public enum PersonalGlucoseHistory {
    public struct Reading: Identifiable, Equatable, Sendable {
        public let id: String
        public let timestamp: Double
        public let mgDL: Double
        public let sourceID: String
        public let sourceName: String
        public let manuallyEntered: Bool
        public init(id: String, timestamp: Double, mgDL: Double, sourceID: String,
                    sourceName: String, manuallyEntered: Bool = false) {
            self.id = id; self.timestamp = timestamp; self.mgDL = mgDL
            self.sourceID = sourceID; self.sourceName = sourceName
            self.manuallyEntered = manuallyEntered
        }
    }

    public static func normalized(_ readings: [Reading], from: Double, through: Double) -> [Reading] {
        guard from.isFinite, through.isFinite, through >= from else { return [] }
        var byID: [String: Reading] = [:]
        var conflicts = Set<String>()
        for reading in readings {
            guard !reading.id.isEmpty, !reading.sourceID.isEmpty, reading.timestamp.isFinite,
                  reading.mgDL.isFinite, reading.mgDL > 0,
                  reading.timestamp >= from, reading.timestamp <= through else { continue }
            if let old = byID[reading.id], old != reading { conflicts.insert(reading.id) }
            byID[reading.id] = reading
        }
        return byID.values.filter { !conflicts.contains($0.id) }.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
    }
}
