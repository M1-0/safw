import Foundation
import WhoopProtocol

/// Completeness of the measured 1 Hz HR stream, not a probability of physiological accuracy.
public enum PersonalSignalCoverage {
    public struct Report: Equatable, Sendable {
        public let expectedSeconds: Int
        public let observedSeconds: Int
        public let conflictingSeconds: Int
        public let longestGapSeconds: Int
        public var fraction: Double { Double(observedSeconds) / Double(expectedSeconds) }
    }

    public static func analyze(_ samples: [HRSample], from: Int, to: Int) -> Report? {
        // Bounded to one sleep block. Refuse reversed/malformed bounds before allocating.
        guard from >= 0, to > from, to - from <= 48 * 3_600 else { return nil }
        var bySecond: [Int: Int] = [:]
        var conflicts = Set<Int>()
        for sample in samples where sample.ts >= from && sample.ts < to && (30...220).contains(sample.bpm) {
            if let old = bySecond[sample.ts], old != sample.bpm { conflicts.insert(sample.ts) }
            bySecond[sample.ts] = sample.bpm
        }
        for ts in conflicts { bySecond.removeValue(forKey: ts) }
        var run = 0, longest = 0
        for ts in from..<to {
            run = bySecond[ts] == nil ? run + 1 : 0
            longest = max(longest, run)
        }
        return Report(expectedSeconds: to - from, observedSeconds: bySecond.count,
                      conflictingSeconds: conflicts.count, longestGapSeconds: longest)
    }
}
