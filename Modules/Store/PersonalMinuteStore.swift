import Foundation
import GRDB
import WhoopProtocol
import WhoopStore

// Additive iPhone research partition in the existing SQLite database. Upstream's
// migrations and canonical metrics are unchanged. This partition has its own version
// record to avoid colliding with the rapidly evolving upstream migration identifiers.
// Android does not consume this optional personal research partition.
public struct PersonalMinuteRow: Codable, Equatable, Sendable {
    public let deviceID: String
    public let end: Int
    public let algorithm: String
    public let payload: String
    public init(deviceID: String, end: Int, algorithm: String, payload: String) {
        self.deviceID = deviceID; self.end = end; self.algorithm = algorithm; self.payload = payload
    }
}

public actor PersonalMinuteStore {
    private let dbWriter: any DatabaseWriter
    public init(store: WhoopStore) { dbWriter = store.registryWriter }
    private func syncRead<T>(_ block: (Database) throws -> T) throws -> T { try dbWriter.read(block) }
    private func syncWrite<T>(_ block: (Database) throws -> T) throws -> T { try dbWriter.write(block) }

    private func migratePersonalMinutes() throws {
        try syncWrite { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS personalSchemaMigration (version TEXT PRIMARY KEY NOT NULL)")
            let applied = try String.fetchOne(db, sql: "SELECT version FROM personalSchemaMigration WHERE version = 'stress-minutes-v1'")
            guard applied == nil else { return }
            try db.execute(sql: """
                CREATE TABLE personalStressMinute (
                    deviceId TEXT NOT NULL REFERENCES device(id) ON DELETE CASCADE,
                    endTs INTEGER NOT NULL,
                    algorithmVersion TEXT NOT NULL,
                    source TEXT NOT NULL DEFAULT 'hrSample+gravitySample',
                    metricType TEXT NOT NULL DEFAULT 'physiological_stress_research',
                    unit TEXT NOT NULL DEFAULT '0..3',
                    derived INTEGER NOT NULL DEFAULT 1,
                    payload TEXT NOT NULL,
                    batchId TEXT NOT NULL,
                    createdAt INTEGER NOT NULL,
                    updatedAt INTEGER NOT NULL,
                    PRIMARY KEY (deviceId, endTs, algorithmVersion)
                )
                """)
            try db.execute(sql: "INSERT INTO personalSchemaMigration(version) VALUES ('stress-minutes-v1')")
        }
    }

    public func personalMinutes(deviceID: String, algorithm: String, from: Int, to: Int) async throws -> [PersonalMinuteRow] {
        try migratePersonalMinutes()
        return try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT endTs, payload FROM personalStressMinute WHERE deviceId = ? AND algorithmVersion = ? AND endTs >= ? AND endTs <= ? ORDER BY endTs", arguments: [deviceID, algorithm, from, to]).map {
                PersonalMinuteRow(deviceID: deviceID, end: $0["endTs"], algorithm: algorithm, payload: $0["payload"])
            }
        }
    }

    public func savePersonalMinutes(_ rows: [PersonalMinuteRow], batch: String, now: Int) async throws {
        try migratePersonalMinutes()
        try syncWrite { db in
            for r in rows {
                try db.execute(sql: """
                    INSERT INTO personalStressMinute(deviceId, endTs, algorithmVersion, payload, batchId, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, endTs, algorithmVersion) DO UPDATE SET
                        payload = excluded.payload, batchId = excluded.batchId, updatedAt = excluded.updatedAt
                    """, arguments: [r.deviceID, r.end, r.algorithm, r.payload, batch, now, now])
            }
        }
    }

    // Deliberately avoids hrSamples' PPG-estimate fallback, which loses per-sample origin
    // at that API boundary. Research provenance must say what actually entered the model.
    public func personalMeasuredHR(deviceID: String, from: Int, to: Int) async throws -> [HRSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT ts, bpm FROM hrSample WHERE deviceId = ? AND ts >= ? AND ts < ? ORDER BY ts LIMIT 200000", arguments: [deviceID, from, to]).map {
                HRSample(ts: $0["ts"], bpm: $0["bpm"])
            }
        }
    }

    // Read current classifications, including a night that STARTED before the query boundary.
    // No LIMIT: silently truncating exclusions would make old sleep eligible as daytime rest.
    public func personalSleepExclusions(deviceID: String, from: Int, to: Int) async throws -> [PersonalMinuteStress.Exclusion] {
        guard from >= 0, to > from else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT COALESCE(startTsAdjusted, startTs) AS effectiveStart, endTs
                FROM sleepSession
                WHERE deviceId IN (?, ?)
                  AND COALESCE(startTsAdjusted, startTs) >= 0
                  AND endTs > COALESCE(startTsAdjusted, startTs)
                  AND COALESCE(startTsAdjusted, startTs) < ? AND endTs > ?
                ORDER BY effectiveStart, endTs
                """, arguments: [deviceID, deviceID + "-noop", to, from]).map {
                    PersonalMinuteStress.Exclusion(start: $0["effectiveStart"], end: $0["endTs"])
                }
        }
    }
}
