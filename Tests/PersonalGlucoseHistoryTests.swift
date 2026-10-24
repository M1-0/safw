import XCTest
@testable import SafwResearch

final class PersonalGlucoseHistoryTests: XCTestCase {
    typealias Reading = PersonalGlucoseHistory.Reading
    func row(_ id: String, time: Double = 200, value: Double = 100, source: String = "meter", manual: Bool = false) -> Reading {
        Reading(id: id, timestamp: time, mgDL: value, sourceID: source, sourceName: source, manuallyEntered: manual)
    }
    func testNoReadingsNoInventedGlucose() {
        XCTAssertTrue(PersonalGlucoseHistory.normalized([], from: 100, through: 300).isEmpty)
    }
    func testOnlyFinitePositiveReadingsWithinRequestedHistory() {
        let rows = [row("old", time: 99), row("future", time: 301), row("nan", value: .nan),
                    row("infinite", value: .infinity), row("zero", value: 0), row("negative", value: -1),
                    row("time", time: .nan), row("", source: "meter"), row("source", source: ""), row("good")]
        XCTAssertEqual(PersonalGlucoseHistory.normalized(rows, from: 100, through: 300), [row("good")])
    }
    func testDuplicatesAndConflictsAreDeterministic() {
        let rows = [row("a"), row("a"), row("b", value: 90), row("b", value: 120)]
        let result = PersonalGlucoseHistory.normalized(rows, from: 100, through: 300)
        XCTAssertEqual(result, [row("a")])
        XCTAssertEqual(result, PersonalGlucoseHistory.normalized(Array(rows.reversed()), from: 100, through: 300))
    }
    func testSourcesAndManualProvenanceRemainSeparate() {
        let rows = [row("b", source: "meter-B"), row("a", source: "Health", manual: true)]
        let result = PersonalGlucoseHistory.normalized(rows, from: 100, through: 300)
        XCTAssertEqual(result.map(\.id), ["a", "b"])
        XCTAssertTrue(result[0].manuallyEntered)
        XCTAssertEqual(result[1].sourceID, "meter-B")
        XCTAssertEqual(result.count, 2)
    }
    func testMalformedBoundsCannotExposeRecords() {
        XCTAssertTrue(PersonalGlucoseHistory.normalized([row("a")], from: .nan, through: 300).isEmpty)
        XCTAssertTrue(PersonalGlucoseHistory.normalized([row("a")], from: 300, through: 100).isEmpty)
    }
}
