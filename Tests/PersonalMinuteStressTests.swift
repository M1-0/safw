import XCTest
import WhoopProtocol
@testable import SafwResearch

final class PersonalMinuteStressTests: XCTestCase {
    let start = 1_800_000_000 // divisible by 300; no dependency on wall time or timezone.
    func heart(_ bpm: Int, seconds: Int = 600) -> [HRSample] {
        (0..<seconds).map { HRSample(ts: start + $0, bpm: bpm) }
    }
    func motion(seconds: Int = 600, moving: Bool = false) -> [GravitySample] {
        (-1..<seconds).map { GravitySample(ts: start + $0, x: moving && $0 % 2 == 0 ? 1 : 0, y: 0, z: 1) }
    }
    var reference: [PersonalMinuteStress.Reference] {
        (1...12).map { .init(end: start - $0 * 300, meanHR: 65) }
    }
    func testNoSignalNeverCreatesZero() {
        let p = PersonalMinuteStress.analyze(hr: [], gravity: [], from: start, to: start + 600, history: reference)
        XCTAssertEqual(p.count, 10)
        XCTAssertTrue(p.allSatisfy { $0.level == nil && $0.reason == .insufficientSignal })
    }
    func testRespondsMonotonicallyToSeveralInputs() throws {
        let levels = try [55, 65, 75, 90, 110].map { bpm -> Double in
            let p = PersonalMinuteStress.analyze(hr: heart(bpm), gravity: motion(), from: start, to: start + 600, history: reference)
            return try XCTUnwrap(p.last?.level)
        }
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertGreaterThan(Set(levels).count, 4)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0 && $0 <= 3 })
        XCTAssertLessThan(levels[1], 1)
    }
    func testDuplicatePacketsCannotFillMissingSeconds() {
        let sparse = [HRSample](repeating: HRSample(ts: start + 599, bpm: 70), count: 500)
        let p = PersonalMinuteStress.analyze(hr: sparse, gravity: motion(), from: start, to: start + 600, history: reference)
        XCTAssertNil(p.last?.level)
        XCTAssertLessThan(p.last!.coverage, 0.01)
    }
    func testConflictingDuplicatesAreNotAnArbitraryWinner() {
        let input = heart(65) + heart(90)
        let p = PersonalMinuteStress.analyze(hr: input, gravity: motion(), from: start, to: start + 600, history: reference)
        XCTAssertEqual(p.last?.coverage, 0)
        XCTAssertNil(p.last?.level)
    }
    func testHighCoverageWithLongHoleFailsContinuity() {
        let h = heart(80).filter { $0.ts < start + 440 || $0.ts >= start + 465 }
        let p = PersonalMinuteStress.analyze(hr: h, gravity: motion(), from: start, to: start + 600, history: reference)
        XCTAssertGreaterThan(p.last!.coverage, 0.9)
        XCTAssertEqual(p.last?.reason, .insufficientSignal)
    }
    func testMissingMotionIsNotStillness() {
        let p = PersonalMinuteStress.analyze(hr: heart(80), gravity: [], from: start, to: start + 600, history: reference)
        XCTAssertEqual(p.last?.reason, .motionUnavailable)
        XCTAssertNil(p.last?.level)
    }
    func testMovementCannotBecomeStressAndCooldownPersists() {
        let g = motion(seconds: 1200).map { p in
            GravitySample(ts: p.ts, x: p.ts < start + 600 && p.ts % 2 == 0 ? 1 : 0, y: 0, z: 1)
        }
        let p = PersonalMinuteStress.analyze(hr: heart(100, seconds: 1200), gravity: g, from: start, to: start + 1200, history: reference)
        XCTAssertEqual(p.last?.reason, .activity)
        XCTAssertNil(p.last?.level)
    }
    func testExcludedSleepAndWorkoutNeverScore() {
        let p = PersonalMinuteStress.analyze(hr: heart(80), gravity: motion(), from: start, to: start + 600,
            history: reference, excluding: [.init(start: start, end: start + 600)])
        XCTAssertTrue(p.allSatisfy { $0.level == nil && $0.reason == .excluded })
    }
    func testFutureAndOverlappingReferencesCannotCalibratePast() {
        let future = (1...20).map { PersonalMinuteStress.Reference(end: start + $0 * 300, meanHR: 60) }
        let p = PersonalMinuteStress.analyze(hr: heart(80), gravity: motion(), from: start, to: start + 600, history: future)
        XCTAssertEqual(p.last?.reason, .baselineUnavailable)
    }
    func testFirstDayLearnsFromNonoverlappingActualWindows() {
        let p = PersonalMinuteStress.analyze(hr: heart(65, seconds: 3000), gravity: motion(seconds: 3000), from: start, to: start + 3000)
        XCTAssertNil(p.first?.level)
        XCTAssertNotNil(p.last?.level)
        XCTAssertLessThanOrEqual(p.last!.confidence, 0.5)
    }
    func testCurrentMinuteIsFreshAndNoLastGoodCarry() {
        let h = heart(65).filter { $0.ts < start + 540 }
        let p = PersonalMinuteStress.analyze(hr: h, gravity: motion(), from: start, to: start + 600, history: reference)
        XCTAssertNil(PersonalMinuteStress.current(p, now: start + 610)?.level)
        XCTAssertNil(PersonalMinuteStress.current(p, now: start + 660))
        XCTAssertNil(PersonalMinuteStress.current(p, now: start + 599))
    }
    func testCompletedMinutesAndDurationAreNotWindowDurations() {
        let p = PersonalMinuteStress.analyze(hr: heart(65), gravity: motion(), from: start, to: start + 619, history: reference)
        XCTAssertEqual(p.last?.end, start + 600)
        let total = (0...2).reduce(0) { $0 + PersonalMinuteStress.minutes(p + p, in: $1) }
        XCTAssertEqual(total, p.filter { $0.level != nil }.count)
        XCTAssertLessThanOrEqual(total, 10)
    }
    func testOrderingDoesNotAlterResults() {
        let a = PersonalMinuteStress.analyze(hr: heart(70), gravity: motion(), from: start, to: start + 600, history: reference)
        let b = PersonalMinuteStress.analyze(hr: Array(heart(70).reversed()), gravity: Array(motion().reversed()), from: start, to: start + 600, history: Array(reference.reversed()))
        XCTAssertEqual(a, b)
    }
}
