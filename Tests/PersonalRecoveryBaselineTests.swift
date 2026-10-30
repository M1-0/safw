import XCTest
@testable import StrandAnalytics

final class PersonalRecoveryBaselineTests: XCTestCase {
    private func baseline(_ value: Double, _ status: BaselineStatus) -> BaselineState {
        BaselineState(baseline: value, spread: 2, nValid: status == .calibrating ? 0 : 20,
                      nightsSinceUpdate: status == .stale ? 20 : 0, status: status)
    }
    private var hrv: BaselineState { baseline(50, .trusted) }

    private func score(resp: BaselineState? = nil, effort: BaselineState? = nil) -> Double? {
        RecoveryScorer.recovery(hrv: 50, rhr: 60, resp: 20, hrvBaseline: hrv,
            rhrBaseline: nil, respBaseline: resp, sleepPerf: 0.85,
            effortBaseline: effort, priorDayEffort: 80)
    }

    func testUncalibratedAndStaleOptionalBaselinesAreAbsent() {
        for status in [BaselineStatus.calibrating, .stale] {
            XCTAssertEqual(score(resp: baseline(15, status)), score())
            XCTAssertEqual(score(effort: baseline(40, status)), score())
            XCTAssertEqual(score(resp: baseline(15, status), effort: baseline(40, status)), score())
        }
    }

    func testUsableOptionalBaselinesStillContribute() throws {
        for status in [BaselineStatus.provisional, .trusted] {
            XCTAssertLessThan(try XCTUnwrap(score(resp: baseline(15, status))), try XCTUnwrap(score()))
            XCTAssertLessThan(try XCTUnwrap(score(effort: baseline(40, status))), try XCTUnwrap(score()))
        }
    }

    func testRespirationRowsAndTraceAgreeWithHeadline() {
        for status in [BaselineStatus.calibrating, .stale, .provisional, .trusted] {
            let resp = baseline(15, status)
            let rows = RecoveryScorer.chargeDrivers(hrv: 50, rhr: 60, resp: 20,
                hrvBaseline: hrv, rhrBaseline: nil, respBaseline: resp, sleepPerf: 0.85)
            let absent = RecoveryScorer.chargeDrivers(hrv: 50, rhr: 60, resp: 20,
                hrvBaseline: hrv, rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.85)
            let (value, trace) = RecoveryScorer.recoveryTrace(hrv: 50, rhr: 60, resp: 20,
                hrvBaseline: hrv, rhrBaseline: nil, respBaseline: resp, sleepPerf: 0.85)
            XCTAssertEqual(value, score(resp: resp))
            XCTAssertEqual(trace.contains { $0.contains("charge term resp ") }, resp.usable)
            XCTAssertEqual(trace.contains { $0.contains("charge baseline resp ") }, resp.usable)
            if resp.usable { XCTAssertNotEqual(rows, absent) }
            else { XCTAssertEqual(rows, absent) }
        }
    }
}
