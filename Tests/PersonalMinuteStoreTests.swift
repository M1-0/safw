import XCTest
import GRDB
import WhoopStore
@testable import SafwResearch

final class PersonalMinuteStoreTests: XCTestCase {
    func testMigrationIsAdditiveAndUpsertIsScopedAndIdempotent() async throws {
        let store = try await WhoopStore.inMemory()
        let minutes = PersonalMinuteStore(store: store)
        try await store.upsertDevice(id: "a", mac: nil, name: nil)
        try await store.upsertDevice(id: "b", mac: nil, name: nil)
        _ = try await store.upsertMetricSeries([MetricPoint(day: "2026-10-08", key: "hrv", value: 48)], deviceId: "a")
        let a = PersonalMinuteRow(deviceID: "a", end: 120, algorithm: "v1", payload: "{\"level\":1}")
        let b = PersonalMinuteRow(deviceID: "b", end: 120, algorithm: "v1", payload: "{\"level\":2}")
        let version2 = PersonalMinuteRow(deviceID: "a", end: 120, algorithm: "v2", payload: "{\"level\":3}")
        try await minutes.savePersonalMinutes([a, b, version2], batch: "first", now: 200)
        try await minutes.savePersonalMinutes([a], batch: "repeat", now: 300)
        let results = try await minutes.personalMinutes(deviceID: "a", algorithm: "v1", from: 0, to: 1000)
        XCTAssertEqual(results, [a])
        let other = try await minutes.personalMinutes(deviceID: "b", algorithm: "v1", from: 0, to: 1000)
        XCTAssertEqual(other, [b])
        let next = try await minutes.personalMinutes(deviceID: "a", algorithm: "v2", from: 0, to: 1000)
        XCTAssertEqual(next, [version2])
        let raw = try await store.metricSeries(deviceId: "a", key: "hrv", from: "2026-10-08", to: "2026-10-08")
        XCTAssertEqual(raw.first?.value, 48)
        let stamps = try await store.registryWriter.read { db -> [Int] in
            let r = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT createdAt, updatedAt, derived FROM personalStressMinute WHERE deviceId='a' AND algorithmVersion='v1'"))
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM personalSchemaMigration"), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT source FROM personalStressMinute LIMIT 1"), "hrSample+gravitySample")
            return [r["createdAt"], r["updatedAt"], r["derived"]]
        }
        XCTAssertEqual(stamps, [200, 300, 1])
        try await store.deleteAllData(deviceId: "a")
        let deleted = try await minutes.personalMinutes(deviceID: "a", algorithm: "v1", from: 0, to: 1000)
        let preserved = try await minutes.personalMinutes(deviceID: "b", algorithm: "v1", from: 0, to: 1000)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(preserved, [b])
    }
    func testFailedBatchRollsBackAndMeasuredHRDoesNotReadPPGFallback() async throws {
        let store = try await WhoopStore.inMemory()
        let minutes = PersonalMinuteStore(store: store)
        try await store.upsertDevice(id: "a", mac: nil, name: nil)
        let good = PersonalMinuteRow(deviceID: "a", end: 60, algorithm: "v1", payload: "{}")
        let foreign = PersonalMinuteRow(deviceID: "missing", end: 60, algorithm: "v1", payload: "{}")
        do {
            try await minutes.savePersonalMinutes([good, foreign], batch: "invalid", now: 200)
            XCTFail("Foreign device should reject the batch")
        } catch { }
        let rows = try await minutes.personalMinutes(deviceID: "a", algorithm: "v1", from: 0, to: 100)
        XCTAssertTrue(rows.isEmpty)
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('a',60,64)")
            try db.execute(sql: "INSERT INTO ppgHrSample(deviceId,ts,bpm,conf) VALUES ('a',61,80,0.9)")
        }
        let h = try await minutes.personalMeasuredHR(deviceID: "a", from: 0, to: 100)
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h.first?.bpm, 64)
    }
}
