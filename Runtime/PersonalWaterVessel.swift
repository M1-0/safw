// Copyright 2026 NoopApp. PolyForm Noncommercial 1.0.0.
// Vessel renderer adapted from ryanbr/noop 4667cb3dab02bd8ed990b09821bbbb6a6db94029.
// The current upstream simulation and motion policy are reused. Metric values are unchanged.
#if os(iOS) && MYNOOP_PERSONAL
import SwiftUI
import StrandDesign

struct PersonalWaterVessel: View {
    let value: Double?
    let tint: Color
    var animated: Bool = true
    var tapPassesThrough: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var sim: LiquidSim
    @State private var splashes = 0

    init(value: Double?, tint: Color, animated: Bool = true, tapPassesThrough: Bool = false) {
        self.value = value
        self.tint = tint
        self.animated = animated
        self.tapPassesThrough = tapPassesThrough
        _sim = State(initialValue: LiquidSim(target: value ?? 0))
    }

    var body: some View {
        Group {
            if animated && value != nil && scenePhase == .active && !motion.poseStill(reduceMotion) {
                liveVessel
            } else {
                Canvas { context, size in
                    PersonalWaterRender.vessel(context, size, LiquidSim.posed(value ?? 0),
                                               now: 0, tint: tint)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
    }

    private var liveVessel: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let now = liquidSeconds(timeline.date)
            Canvas { context, size in
                sim.step(now: now, tilt: LiquidMotion.shared.tilt, target: value ?? 0)
                PersonalWaterRender.vessel(context, size, sim, now: now, tint: tint)
            }
        }
        .modifier(PersonalWaterTap(passesThrough: tapPassesThrough) {
            sim.splash(12)
            splashes &+= 1
        })
        .liquidTapHaptic(trigger: splashes)
        .onAppear {
            sim.restartClock()
            LiquidMotion.shared.acquire()
        }
        .onDisappear { LiquidMotion.shared.release() }
    }
}

private struct PersonalWaterTap: ViewModifier {
    let passesThrough: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if passesThrough {
            content.simultaneousGesture(TapGesture().onEnded { action() })
        } else {
            content.onTapGesture(perform: action)
        }
    }
}

enum PersonalWaterRender {

    /// A circular vessel of liquid filled to `sim.level`, tinted, with parallax
    /// slosh, a light band that follows tilt, surface glints, flake and droplets.
    static func vessel(_ base: GraphicsContext, _ size: CGSize, _ sim: LiquidSim, now: Double, tint: Color) {
        // Floor at 1 so a degenerate sub-3pt Canvas can't drive R negative (negative well rect / chord math).
        let R = max(1, min(size.width, size.height) / 2 - 1.5)
        let ext = R * 1.8
        let cx = size.width / 2, cy = size.height / 2
        let well = CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)

        var ctx = base
        ctx.translateBy(x: cx, y: cy)
        ctx.fill(Path(ellipseIn: well), with: .color(NoopVisualStyle.inset))

        var body = ctx
        body.clip(to: Path(ellipseIn: well))

        let lv = sim.level
        if lv > 0.004 {
            let sy = R * (1 - 2 * min(0.985, lv))
            let amp = (0.018 + sim.energy * 0.09) * R

            // helper to build a wave polygon in a given (already-transformed) context
            func wavePolygon(_ w: (Double) -> Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: -ext, y: w(-ext)))
                var x = -ext + 4
                while x <= ext { p.addLine(to: CGPoint(x: x, y: w(x))); x += 4 }
                p.addLine(to: CGPoint(x: ext, y: w(ext)))
                p.addLine(to: CGPoint(x: ext, y: R * 2.4))
                p.addLine(to: CGPoint(x: -ext, y: R * 2.4))
                p.closeSubpath()
                return p
            }
            func surfaceLine(_ w: (Double) -> Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: -ext, y: w(-ext)))
                var x = -ext + 4
                while x <= ext { p.addLine(to: CGPoint(x: x, y: w(x))); x += 4 }
                p.addLine(to: CGPoint(x: ext, y: w(ext)))
                return p
            }

            // back parallax layer
            let syB = sy - R * 0.04
            let hwB = liquidChordHW(R, syB)
            let wB: (Double) -> Double = {
                liquidWave($0, amp: amp, R: R, hw: hwB, curl: liquidCurl(sim.abv),
                           ph1: sim.p1 * 0.92 + 2.1, ph2: sim.p2 * 0.9 + 1.3, ampMul: 1.35)
            }
            var backCtx = body
            backCtx.translateBy(x: 0, y: syB)
            backCtx.rotate(by: .radians(sim.ab))
            backCtx.fill(wavePolygon(wB), with: .color(tint.opacity(0.28)))

            // main body
            let hw = liquidChordHW(R, sy)
            let w: (Double) -> Double = {
                liquidWave($0, amp: amp, R: R, hw: hw, curl: liquidCurl(sim.av),
                           ph1: sim.p1, ph2: sim.p2, ampMul: 1)
            }
            var mainCtx = body
            mainCtx.translateBy(x: 0, y: sy)
            mainCtx.rotate(by: .radians(sim.a))
            mainCtx.fill(wavePolygon(w),
                         with: .linearGradient(Gradient(colors: [tint.opacity(0.74),
                                                                  tint.liquidDarker(0.28).opacity(0.80)]),
                                               startPoint: CGPoint(x: 0, y: -amp),
                                               endPoint: CGPoint(x: 0, y: R * 1.7)))

            // a sheet of light gliding across as you tilt
            var bandCtx = mainCtx
            bandCtx.clip(to: wavePolygon(w))
            let bandX = -sim.a * R * 2.2 + sin(now * 0.3) * R * 0.15
            bandCtx.fill(Path(CGRect(x: -R * 2.4, y: -R * 2.4, width: R * 4.8, height: R * 4.8)),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.06), .white.opacity(0)]),
                                               startPoint: CGPoint(x: bandX - R * 1.2, y: 0),
                                               endPoint: CGPoint(x: bandX + R * 1.2, y: 0)))

            // surface sheen + glints + line
            mainCtx.fill(Path(CGRect(x: -ext, y: 0, width: ext * 2, height: R * 0.15)),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0.09), .white.opacity(0)]),
                                               startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: R * 0.15)))
            var gx = -hw
            while gx <= hw {
                let slope = (w(gx + 3) - w(gx - 3)) / 6
                if abs(slope) < 0.05 {
                    let o = 0.22 * (1 - abs(slope) / 0.05)
                    mainCtx.fill(Path(CGRect(x: gx - 2, y: w(gx) - 0.8, width: 4, height: 1.4)), with: .color(.white.opacity(o)))
                }
                gx += 6
            }
            mainCtx.stroke(surfaceLine(w), with: .color(.white.opacity(0.45)), lineWidth: 1.3)

            // droplets
            for b in sim.drops {
                let rr = max(0.7, b.r * R)
                mainCtx.fill(Path(ellipseIn: CGRect(x: b.x * R - rr, y: b.y * R - rr, width: 2 * rr, height: 2 * rr)),
                             with: .color(.white.opacity(min(0.55, b.life * 0.5) * 0.5)))
            }

            // suspended flake (circle frame, only inside the liquid)
            let sa = sin(sim.a), ca = cos(sim.a)
            for f in sim.flecks {
                let fx = f.x * R, fy = f.y * R
                if fx * fx + fy * fy > R * R * 0.9 { continue }
                if -fx * sa + (fy - sy) * ca < R * 0.02 { continue }
                let sVal = sin(f.ph + fx * 0.12 + sim.a * 5 + now * f.sp)
                let spark = pow(max(0, sVal), 10)
                let sz = 0.7 + f.z * 1.0 + spark * 1.4
                let shade: Color
                switch f.kind {
                case 2: shade = NoopVisualStyle.inset.opacity(0.12 + spark * 0.22)
                case 1: shade = tint.liquidMix(.white, 0.55).opacity(0.10 + spark * 0.8)
                default: shade = .white.opacity(0.08 * f.z + spark * 0.85)
                }
                body.fill(Path(CGRect(x: fx - sz / 2, y: fy - sz / 2, width: sz, height: sz)), with: .color(shade))
            }
        }

        // inner top shadow
        body.fill(Path(CGRect(x: -R, y: -R, width: 2 * R, height: R * 0.75)),
                  with: .linearGradient(Gradient(colors: [.black.opacity(0.30), .black.opacity(0)]),
                                        startPoint: CGPoint(x: 0, y: -R), endPoint: CGPoint(x: 0, y: -R * 0.30)))
        // soft top-left highlight
        body.fill(Path(ellipseIn: CGRect(x: -R * 0.72, y: -R * 0.78, width: R * 0.9, height: R * 0.5)),
                  with: .radialGradient(Gradient(colors: [.white.opacity(0.09), .white.opacity(0)]),
                                        center: CGPoint(x: -R * 0.27, y: -R * 0.5), startRadius: 0, endRadius: R * 0.55))
        // rim
        ctx.stroke(Path(ellipseIn: well), with: .color(tint.opacity(0.22)), lineWidth: 1.25)
    }


}
#endif
