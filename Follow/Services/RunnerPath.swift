import CoreGraphics
import Foundation

/// How the student's animal gets from the title to the deadline track (D44), picked in Settings.
enum RunnerStyle: String, CaseIterable, Identifiable {
    /// A leap over the name, then hops along the toolbar.
    case hop
    /// A fast low sprint that slides a little past its spot and steps back.
    case dash

    var id: Self { self }
    var title: String {
        switch self {
        case .hop: "Hops"
        case .dash: "Dash"
        }
    }

    static let key = "runner.style"
    static let speedKey = "runner.speed"
    /// The speeds Settings offers; 1 is the designed pace.
    static let speeds = 0.5...2.0
}

/// The run as a function of time, so the view only draws: where the animal is and how it is squashed.
/// Points are in a top-left space (y grows down), like SwiftUI.
struct RunnerPath {
    struct Pose: Equatable {
        /// The middle of the animal.
        var center: CGPoint
        /// Its font size.
        var size: CGFloat
        /// Wider and lower on the ground, thinner and taller in the air.
        var stretch = CGSize(width: 1, height: 1)
        /// Degrees it leans toward the flag.
        var tilt = 0.0
        /// 0…1, how fast it moves: the dash draws speed lines from it.
        var speed = 0.0
        /// False in the title, where the animal still faces the name.
        var facesFlag = true
    }

    /// A bit of dust at the animal's feet where it takes off or lands.
    struct Puff: Equatable {
        let time: Double
        let point: CGPoint
    }

    let duration: Double
    private let style: RunnerStyle
    private let from: CGPoint
    private let to: CGPoint
    private let fromSize: CGFloat
    private let toSize: CGFloat
    private let hops: [Hop]
    private let pace: Double

    /// One jump: between two fractions of the way, `height` high, between two times.
    private struct Hop {
        let start: Double
        let end: Double
        let height: CGFloat
        let begins: Double
        let ends: Double
    }

    // Seconds at speed 1.
    private static let windUp = 0.12
    private static let leapTime = 0.34
    private static let hopTime = 0.2
    private static let settle = 0.16
    private static let dashTime = 0.65
    /// The part of the dash that runs out; the rest steps back from the overshoot.
    private static let dashSprint = 0.72
    private static let hopLength: CGFloat = 72
    private static let overshoot: CGFloat = 10

    /// - Parameters:
    ///   - clear: how far the first leap must carry to get over the name next to the animal (hops only).
    ///   - leap: how high that first leap is; the hops after it are lower.
    ///   - speed: 1 is the designed pace, 2 takes half the time.
    init(style: RunnerStyle, from: CGPoint, to: CGPoint, fromSize: CGFloat, toSize: CGFloat,
         clear: CGFloat = 0, leap: CGFloat = 14, speed: Double = 1) {
        self.style = style
        self.from = from
        self.to = to
        self.fromSize = fromSize
        self.toSize = toSize
        pace = 1 / min(max(speed, RunnerStyle.speeds.lowerBound), RunnerStyle.speeds.upperBound)
        let distance = hypot(to.x - from.x, to.y - from.y)

        guard style == .hop, distance > 0 else {
            hops = []
            duration = Self.dashTime * pace
            return
        }
        var hops: [Hop] = []
        var time = Self.windUp * pace
        // The leap over the name never takes more than half the way, so hops are left for a short run.
        let first = Double(min(max(clear, 0), distance / 2) / distance)
        if first > 0 {
            hops.append(Hop(start: 0, end: first, height: leap, begins: time, ends: time + Self.leapTime * pace))
            time += Self.leapTime * pace
        }
        let count = max(2, Int(((1 - first) * distance / Self.hopLength).rounded()))
        for i in 0..<count {
            let start = first + (1 - first) * Double(i) / Double(count)
            let end = i == count - 1 ? 1 : first + (1 - first) * Double(i + 1) / Double(count)
            // Each hop is a little lower than the one before, like a ball that loses its bounce.
            let height = leap * (0.95 - 0.25 * Double(i) / Double(count))
            hops.append(Hop(start: start, end: end, height: height, begins: time, ends: time + Self.hopTime * pace))
            time += Self.hopTime * pace
        }
        self.hops = hops
        duration = time + Self.settle * pace
    }

    /// Dust where the dash starts and where each hop lands. The last landing has none: the animal squashes on the track there.
    var puffs: [Puff] {
        guard style == .hop else { return [Puff(time: 0, point: CGPoint(x: from.x, y: from.y + fromSize / 2))] }
        return hops.dropLast().map { hop in
            let landing = point(hop.end)
            return Puff(time: hop.ends, point: CGPoint(x: landing.x, y: landing.y + size(hop.end) / 2))
        }
    }

    func pose(at time: Double) -> Pose {
        guard time > 0 else { return Pose(center: from, size: fromSize, facesFlag: false) }
        guard time < duration else { return Pose(center: to, size: toSize) }
        switch style {
        case .hop: return hopPose(at: time)
        case .dash: return dashPose(at: time / duration)
        }
    }

    private func point(_ fraction: Double) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }

    private func size(_ fraction: Double) -> CGFloat {
        fromSize + (toSize - fromSize) * min(max(fraction, 0), 1)
    }

    private func hopPose(at time: Double) -> Pose {
        let windUp = Self.windUp * pace
        if time < windUp {
            // It crouches and turns to the flag before the first jump.
            let crouch = sin(.pi * time / windUp)
            return Pose(center: from, size: fromSize, stretch: CGSize(width: 1 + 0.15 * crouch, height: 1 - 0.2 * crouch),
                        facesFlag: time > windUp / 2)
        }
        guard let hop = hops.first(where: { time < $0.ends }) else {
            // On the track: one last squash before the runner on the pill takes over.
            let squash = sin(.pi * (time - (hops.last?.ends ?? 0)) / (Self.settle * pace))
            return Pose(center: to, size: toSize, stretch: CGSize(width: 1 + 0.15 * squash, height: 1 - 0.2 * squash))
        }
        let u = (time - hop.begins) / (hop.ends - hop.begins)
        let fraction = hop.start + (hop.end - hop.start) * u
        var center = point(fraction)
        center.y -= 4 * hop.height * u * (1 - u)
        // 0 on the ground, 1 for most of the jump.
        let air = min(1, 12 * u * (1 - u))
        return Pose(center: center, size: size(fraction),
                    stretch: CGSize(width: 1.14 - 0.2 * air, height: 0.84 + 0.24 * air),
                    // Nose up on the way up, down on the way down.
                    tilt: (4 + 12 * (2 * u - 1)) * air)
    }

    private func dashPose(at t: Double) -> Pose {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let over = distance > 0 ? Double(Self.overshoot / distance) : 0
        if t < Self.dashSprint {
            // Fast from the first frame, slower into the spot, and a little past it.
            let u = t / Self.dashSprint
            let fraction = (1 + over) * (1 - pow(1 - u, 3))
            let speed = pow(1 - u, 2)
            return Pose(center: point(fraction), size: size(fraction),
                        stretch: CGSize(width: 1 + 0.12 * speed, height: 1 - 0.06 * speed),
                        tilt: 16 * (1 - u), speed: speed)
        }
        // It brakes, leans back, and steps back onto its spot.
        let u = (t - Self.dashSprint) / (1 - Self.dashSprint)
        let back = u * u * (3 - 2 * u)
        return Pose(center: point(1 + over * (1 - back)), size: toSize, tilt: -6 * sin(.pi * u))
    }
}
