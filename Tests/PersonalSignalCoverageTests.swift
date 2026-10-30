import XCTest
import WhoopProtocol
@testable import SafwResearch

final class PersonalSignalCoverageTests: XCTestCase {
    func testEmptySignalIsZeroCoverageAndFullGap() throws {
        let report = try XCTUnwrap(PersonalSignalCoverage.analyze([], from: 100, to: 700))
        XCTAssertEqual(report.fraction, 0)
        XCTAssertEqual(report.longestGapSeconds, 600)
    }
    func testBoundsAndDuplicatesDoNotFillGaps() throws {
        let samples = [HRSample(ts: 99, bpm: 60), HRSample(ts: 100, bpm: 60),
                       HRSample(ts: 100, bpm: 60), HRSample(ts: 103, bpm: 61), HRSample(ts: 104, bpm: 61)]
        let report = try XCTUnwrap(PersonalSignalCoverage.analyze(samples, from: 100, to: 104))
        XCTAssertEqual(report.observedSeconds, 2)
        XCTAssertEqual(report.longestGapSeconds, 2)
        XCTAssertEqual(report.fraction, 0.5)
    }
    func testConflictsAndInvalidHeartRatesAreMissingRegardlessOfOrder() throws {
        let samples = [HRSample(ts: 100, bpm: 65), HRSample(ts: 100, bpm: 90),
                       HRSample(ts: 101, bpm: 0), HRSample(ts: 102, bpm: 221)]
        let a = PersonalSignalCoverage.analyze(samples, from: 100, to: 103)
        XCTAssertEqual(a, PersonalSignalCoverage.analyze(Array(samples.reversed()), from: 100, to: 103))
        XCTAssertEqual(a?.observedSeconds, 0)
        XCTAssertEqual(a?.conflictingSeconds, 1)
    }
    func testIncompleteEdgesAndInvalidWindows() {
        let samples = (101..<104).map { HRSample(ts: $0, bpm: 65) }
        XCTAssertEqual(PersonalSignalCoverage.analyze(samples, from: 100, to: 107)?.longestGapSeconds, 3)
        XCTAssertNil(PersonalSignalCoverage.analyze([], from: 100, to: 100))
        XCTAssertNil(PersonalSignalCoverage.analyze([], from: 200, to: 100))
        XCTAssertNil(PersonalSignalCoverage.analyze([], from: -1, to: Int.max))
        XCTAssertNil(PersonalSignalCoverage.analyze([], from: 0, to: Int.max))
    }
}
