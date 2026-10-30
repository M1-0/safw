import Foundation
import WhoopProtocol
import StrandAnalytics

// Personal, opt-in research lens. No downstream recovery/sleep/illness consumer.
// This is NOT a reconstruction of WHOOP's unpublished model. The 0...3 display scale
// is shared; the formula is a provisional HR-only deviation measure. Wrist daytime
// RMSSD is intentionally omitted until artifact rejection has independent validation.
public enum PersonalMinuteStress {
    public static let version = "mynoop.minute.hr.v3"
    public static let window = 300
    public static let step = 60
    public static let cooldown = 15 * 60
    // Replay enough completed windows to retain activity suppression across day/batch boundaries.
    public static let warmup = window + cooldown
    public static let historySeconds = 14 * 86_400

    public enum Reason: String, Codable, Sendable {
        case estimate, insufficientSignal, motionUnavailable, activity, excluded, baselineUnavailable
    }
    public struct Point: Codable, Equatable, Sendable {
        public let end: Int // Exclusive end of a completed UTC minute; not a rounded sample timestamp.
        public let level: Double?
        public let meanHR: Double?
        public let coverage: Double
        public let motionCoverage: Double
        public let baseline: Double?
        public let baselineWindows: Int
        public let reason: Reason
        // Input adequacy only, NOT a calibrated probability of accuracy.
        public let confidence: Double
    }
    public struct Reference: Sendable {
        public let end: Int
        public let meanHR: Double
        public init(end: Int, meanHR: Double) { self.end = end; self.meanHR = meanHR }
    }
    public struct Exclusion: Sendable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }
    }

    public static func references(_ points: [Point]) -> [Reference] {
        points.compactMap { p in
            guard p.end % window == 0, p.reason == .estimate || p.reason == .baselineUnavailable,
                  p.end >= window, p.coverage.isFinite, (0.8...1).contains(p.coverage),
                  p.motionCoverage.isFinite, (0.6...1).contains(p.motionCoverage),
                  let mean = p.meanHR, mean.isFinite, (30...220).contains(mean) else { return nil }
            return Reference(end: p.end, meanHR: mean)
        }
    }

    public static func analyze(hr: [HRSample], gravity: [GravitySample], from: Int, to: Int,
                               history: [Reference] = [], excluding: [Exclusion] = []) -> [Point] {
        guard from >= 0, to > from, to <= Int.max - warmup - window,
              to - from <= 48 * 3_600 else { return [] }
        let exclusions = excluding.filter { $0.start >= 0 && $0.end > $0.start }
        // Conflicting HR observations at one second are missing, not votes. Duplicate
        // packets cannot create coverage or push a window over a signal gate.
        var hrBySecond: [Int: Int] = [:]
        var conflicts = Set<Int>()
        for p in hr where p.bpm >= 30 && p.bpm <= 220 && p.ts >= from - window && p.ts < to {
            if let old = hrBySecond[p.ts], old != p.bpm { conflicts.insert(p.ts) }
            hrBySecond[p.ts] = p.bpm
        }
        for ts in conflicts { hrBySecond.removeValue(forKey: ts) }
        // Reuse upstream's gravity-change intensity; never bridge a sensor gap.
        // dynAccel is not silently substituted: it is a different feature distribution.
        var gravityBySecond: [Int: GravitySample] = [:]
        var gravityConflicts = Set<Int>()
        for p in gravity where p.unit == "g" && p.x.isFinite && p.y.isFinite && p.z.isFinite {
            if p.ts >= from - warmup - window - 1 && p.ts < to {
                if let old = gravityBySecond[p.ts], old.x != p.x || old.y != p.y || old.z != p.z {
                    gravityConflicts.insert(p.ts)
                }
                gravityBySecond[p.ts] = p
            }
        }
        for ts in gravityConflicts { gravityBySecond.removeValue(forKey: ts) }
        var movingBySecond: [Int: Bool] = [:]
        for (ts, p) in gravityBySecond {
            guard let prev = gravityBySecond[ts - 1] else { continue }
            let dx = p.x - prev.x, dy = p.y - prev.y, dz = p.z - prev.z
            movingBySecond[ts] = sqrt(dx * dx + dy * dy + dz * dz) >= WorkoutDetector.motionThreshold
        }
        var refs: [Int: Double] = [:]
        var referenceConflicts = Set<Int>()
        for r in history where r.end >= window && r.end <= from && r.end >= from - historySeconds
            && r.end % window == 0 && r.meanHR.isFinite && (30...220).contains(r.meanHR) {
            // Sleep/workout classifications can arrive after these windows were recorded.
            // Recheck the entire historical window, not just its endpoint, on every replay.
            guard !exclusions.contains(where: { $0.start < r.end && $0.end > r.end - window }) else { continue }
            if let old = refs[r.end], old != r.meanHR { referenceConflicts.insert(r.end) }
            refs[r.end] = r.meanHR
        }
        for ts in referenceConflicts { refs.removeValue(forKey: ts) }
        var output: [Point] = []
        var activityUntil = Int.min
        let firstEnd = ((from / step) + 1) * step
        let lastEnd = (to / step) * step
        guard firstEnd <= lastEnd else { return [] }
        for end in stride(from: firstEnd - warmup, through: lastEnd, by: step) {
            let start = end - window
            let motion = (start..<end).compactMap { movingBySecond[$0] }
            let motionCoverage = Double(motion.count) / Double(window)
            // Activity is independent of HR coverage and sleep/workout exclusions. A missing
            // heart-rate packet must not disable a movement-triggered cooldown.
            if motionCoverage >= 0.6 && Double(motion.filter { $0 }.count) / Double(motion.count) >= 0.3 {
                activityUntil = end + cooldown
            }
            guard end >= firstEnd else { continue }
            let values = (start..<end).compactMap { hrBySecond[$0] }
            let coverage = Double(values.count) / Double(window)
            let mean = values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
            let latest = ((end - step)..<end).filter { hrBySecond[$0] != nil }
            let latestMotion = ((end - step)..<end).filter { movingBySecond[$0] != nil }
            var motionMissingRun = 0, longestMotionGap = 0
            for ts in start..<end {
                motionMissingRun = movingBySecond[ts] == nil ? motionMissingRun + 1 : 0
                longestMotionGap = max(longestMotionGap, motionMissingRun)
            }
            var missingRun = 0, longestGap = 0
            for ts in start..<end {
                missingRun = hrBySecond[ts] == nil ? missingRun + 1 : 0
                longestGap = max(longestGap, missingRun)
            }
            let eligible = refs.filter { $0.key <= start && $0.key >= end - historySeconds }.values.sorted()
            let center = eligible.isEmpty ? nil : median(eligible)
            var reason: Reason
            var level: Double?
            if exclusions.contains(where: { $0.start < end && $0.end > start }) {
                reason = .excluded
            } else if coverage < 0.8 || longestGap > 15 || latest.count < 30 || (latest.last ?? 0) < end - 10 {
                reason = .insufficientSignal
            } else if motionCoverage < 0.6 || longestMotionGap > 30 || latestMotion.count < 30 || (latestMotion.last ?? 0) < end - 10 {
                reason = .motionUnavailable
            } else if end <= activityUntil {
                reason = .activity
            } else if eligible.count < 6 {
                reason = .baselineUnavailable
            } else if let center, let mean {
                let mad = median(eligible.map { abs($0 - center) }.sorted())
                let scale = max(8, 1.4826 * mad)
                // The -1 offset puts a usual quiet window below 1, instead of declaring
                // every baseline window medium stress. Coefficients are research defaults.
                let z = max(-8, min(8, (mean - center) / scale - 1))
                level = 3 / (1 + exp(-z))
                reason = .estimate
            } else { reason = .baselineUnavailable }
            let confidence = level == nil ? 0 : min(0.5, coverage * motionCoverage * min(1, Double(eligible.count) / 36) * 0.5)
            let point = Point(end: end, level: level, meanHR: mean, coverage: coverage,
                              motionCoverage: motionCoverage, baseline: center, baselineWindows: eligible.count,
                              reason: reason, confidence: confidence)
            output.append(point)
            if let reference = references([point]).first { refs[reference.end] = reference.meanHR }
        }
        return output
    }

    public static func current(_ points: [Point], now: Int) -> Point? {
        // A fresh missing minute invalidates an older good one; no last-good carry.
        guard let p = points.max(by: { $0.end < $1.end }), p.end <= now, now - p.end < step else { return nil }
        return p
    }
    public static func minutes(_ points: [Point], in band: Int) -> Int {
        Set(points.filter { p in
            guard let v = p.level else { return false }
            return min(2, Int(v)) == band
        }.map(\.end)).count
    }
    private static func median(_ values: [Double]) -> Double {
        let m = values.count / 2
        return values.count % 2 == 0 ? (values[m - 1] + values[m]) / 2 : values[m]
    }
}
