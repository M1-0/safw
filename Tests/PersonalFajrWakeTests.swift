import Foundation
import XCTest
@testable import StrandAnalytics

final class PersonalFajrWakeTests: XCTestCase {
    func testFajrInterruptionRemainsOneNightWithoutCountingWakeAsSleep() throws {
        let start = Int(try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T00:00:00+03:00")).timeIntervalSince1970)
        let wake = start + 5 * 3_600
        for minutesAwake in [2, 25] {
            let resume = wake + minutesAwake * 60
            let end = start + 8 * 3_600
            let blocks = [SleepStageTotals.NightBlock(start: start, end: wake),
                          SleepStageTotals.NightBlock(start: resume, end: end)]
            XCTAssertEqual(SleepStageTotals.mainNightGroupIndices(blocks, offsetSec: 10_800), [0, 1])
            let stages = [(startTs: start, stagesJSON: Optional("[{\"start\":\(start),\"end\":\(wake),\"stage\":\"light\"}]")),
                          (startTs: resume, stagesJSON: Optional("[{\"start\":\(resume),\"end\":\(end),\"stage\":\"light\"}]"))]
            let total = try XCTUnwrap(SleepStageTotals.dailyAggregateHonoringEdits(
                detected: stages, edited: [:], onsetByStart: [start: start, resume: resume], offsetSec: 10_800))
            XCTAssertEqual(total.sleep.totalSleepMin, Double(480 - minutesAwake), accuracy: 0.001)
            XCTAssertEqual(total.sleep.efficiency, Double(480 - minutesAwake) / 480, accuracy: 0.001)
        }
    }
}
