import XCTest
@testable import StrandAnalytics

final class PersonalRecoveryValidityTests: XCTestCase {
    typealias Baseline = RecoveryScorer.DriverBaseline
    func score(hrv: Double = 50, rhr: Double = 60, resp: Double? = nil,
               hrvBaseline: Baseline? = Baseline(mean: 50, spread: 10),
               rhrBaseline: Baseline? = Baseline(mean: 60, spread: 5),
               respBaseline: Baseline? = nil, sleep: Double? = 0.85,
               temperature: Double? = nil, slope: Double? = nil,
               effort: Double? = nil, effortBaseline: Baseline? = nil) -> Double? {
        RecoveryScorer.recovery(hrv: hrv, rhr: rhr, resp: resp,
            hrvBaseline: hrvBaseline, rhrBaseline: rhrBaseline, respBaseline: respBaseline,
            sleepPerf: sleep, skinTempDev: temperature, recoveryIndexSlope: slope,
            effortBaseline: effortBaseline, priorDayEffort: effort)
    }
    func testValidFormulaIsPreserved() throws {
        XCTAssertEqual(try XCTUnwrap(score()), 100 / (1 + exp(-0.32)), accuracy: 1e-12)
        XCTAssertGreaterThan(try XCTUnwrap(score(hrv: 60)), try XCTUnwrap(score(hrv: 40)))
    }
    func testInvalidRequiredDriverNeverProducesAClampedScore() {
        for value in [Double.nan, .infinity, -.infinity, 0, -1] { XCTAssertNil(score(hrv: value)) }
        XCTAssertNil(score(hrvBaseline: nil))
        for b in [Baseline(mean: .nan, spread: 1), Baseline(mean: 50, spread: .infinity), Baseline(mean: 50, spread: -1)] {
            XCTAssertNil(score(hrvBaseline: b))
        }
    }
    func testEveryParticipatingDriverRejectsInvalidInput() {
        XCTAssertNil(score(rhr: .nan))
        XCTAssertNil(score(resp: .infinity, respBaseline: Baseline(mean: 15, spread: 2)))
        XCTAssertNil(score(sleep: .nan))
        XCTAssertNil(score(sleep: 85))
        XCTAssertNil(score(sleep: -0.1))
        XCTAssertNil(score(temperature: .infinity))
        XCTAssertNil(score(slope: .nan))
        XCTAssertNil(score(effort: 101, effortBaseline: Baseline(mean: 40, spread: 5)))
    }
    func testAbsentOptionalTermsAreStillAbsent() {
        XCTAssertEqual(score(rhr: .nan, rhrBaseline: nil), score(rhr: 0, rhrBaseline: nil))
        XCTAssertEqual(score(resp: .nan), score())
        XCTAssertEqual(score(effort: .nan), score())
    }
    func testArithmeticOverflowCannotBecomePerfectRecovery() {
        XCTAssertNil(score(hrv: Double.greatestFiniteMagnitude, hrvBaseline: Baseline(mean: 1, spread: 0)))
        XCTAssertNotNil(score(hrvBaseline: Baseline(mean: 50, spread: 0)))
    }
}
