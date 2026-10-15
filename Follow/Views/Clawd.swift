import SwiftUI

/// Clawd, the Claude Code mascot, as black-and-white pixel art wandering the detail pane (D38).
/// Students report about once a week, so most days are blank; Clawd keeps them company.
/// It lives above the student and group pages, so switching pages doesn't move or reset it.
/// It walks to random spots, blinks and says things now and then; click it for a random trick,
/// right-click to hide it (Settings brings it back).
struct ClawdPlayground: View {
    @AppStorage("clawd.visible") private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var area: CGSize = .zero
    @State private var position: CGPoint?
    @State private var pose = ClawdPose()
    @State private var speech: String?
    @State private var speechID = 0
    @State private var hop: CGFloat = 0
    @State private var spin: Double = 0
    @State private var tilt: Double = 0
    @State private var flip: Double = 0
    @State private var scale: CGFloat = 1
    @State private var queued: ClawdTrick?
    @State private var lastTrick: ClawdTrick?

    static var phrases: [String] {
        [
            "Hello!", "Hehe", "Hehehe", "Hi there!", "Beep boop", "Who's next?", "Keep going!",
            "Any notes today?", "Hmm…", "Nice week!", "I like this project", "*waves*",
            "lol", "brb", "Ship it!", "Works on my machine", "Did you commit?", "You're absolutely right!",
            "Compacting…", "Thinking…", "*vibrates*", "Skill issue", "Coffee?", "I'm not a crab. Probably.",
            "Who touched main?", "rm -rf? No thanks", "Weekend yet?", "Do the students know about me?",
            "Week \(WeekCalendar.week(of: .now).week) already?!",
        ]
    }

    var body: some View {
        if visible {
            // Color.clear takes no clicks, so the board under it stays usable; only Clawd does.
            Color.clear
                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                    area = size
                    position = position.map(clamped)
                }
                .overlay(alignment: .topLeading) {
                    if let position { clawd.offset(x: position.x - Self.size.width / 2, y: position.y - Self.size.height) }
                }
                .task { await live() }
        }
    }

    private static let size = CGSize(width: CGFloat(ClawdPose.width) * ClawdSprite.pixel,
                                     height: CGFloat(ClawdPose.height) * ClawdSprite.pixel)

    private var clawd: some View {
        ClawdSprite(pose: pose)
            .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .rotationEffect(.degrees(flip))
            .scaleEffect(scale, anchor: .bottom)
            .overlay(alignment: .bottom) {
                if let speech {
                    SpeechBubble(text: speech)
                        .fixedSize()
                        .offset(y: -(Self.size.height + 12))
                        .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .offset(y: hop)
            .contentShape(.rect)
            .onTapGesture { queued = ClawdTrick.random(after: lastTrick) }
            .pointerStyle(.link)
            .contextMenu {
                Button("Hide Clawd") { visible = false }
            }
            .accessibilityElement()
            .accessibilityLabel("Clawd")
            .accessibilityAddTraits(.isButton)
            .transition(.opacity)
    }

    // MARK: Behavior

    /// The whole pane, less a margin; the top keeps room for a speech bubble. `position` is Clawd's feet.
    private var walkArea: CGRect {
        let minX = Self.size.width / 2 + 8, minY = Self.size.height + 50
        return CGRect(x: minX, y: minY,
                      width: max(area.width - 2 * minX, 0), height: max(area.height - 8 - minY, 0))
    }

    /// A random spot, preferring one far enough away to make a real walk.
    private func randomSpot() -> CGPoint {
        let rect = walkArea
        func spot() -> CGPoint { CGPoint(x: .random(in: rect.minX...rect.maxX), y: .random(in: rect.minY...rect.maxY)) }
        guard let here = position else { return spot() }
        let candidates = (0..<4).map { _ in spot() }
        return candidates.max { hypot($0.x - here.x, $0.y - here.y) < hypot($1.x - here.x, $1.y - here.y) }!
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let rect = walkArea
        return CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }

    private func live() async {
        while area == .zero, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
        withAnimation { position = position ?? randomSpot() }
        while !Task.isCancelled {
            if let trick = queued {
                queued = nil
                lastTrick = trick
                await perform(trick)
            } else if !reduceMotion, Double.random(in: 0..<1) < 0.07 {
                // Now and then a trick on its own, nobody asked.
                let trick = ClawdTrick.random(after: lastTrick)
                lastTrick = trick
                await perform(trick)
            } else if !reduceMotion, Double.random(in: 0..<1) < 0.8 {
                await walk(to: randomSpot())
            } else {
                await idle(for: .random(in: 1...3.5))
            }
        }
    }

    /// Waits in short slices so a click is answered right away; false when interrupted.
    private func pause(_ seconds: Double) async -> Bool {
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            if Task.isCancelled || queued != nil { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private func idle(for seconds: Double) async {
        pose.look = .random(in: -1...1)
        if Double.random(in: 0..<1) < 0.3 { say(Self.phrases.randomElement()!) }
        var left = seconds
        while left > 0 {
            let slice = min(left, .random(in: 1.2...3))
            guard await pause(slice) else { return }
            left -= slice
            await blink()
        }
    }

    /// Walks in a straight line at `speed` points per second; `backwards` faces away (a moonwalk).
    private func walk(to target: CGPoint, speed: Double = .random(in: 50...90), backwards: Bool = false) async {
        let tick = 1.0 / 30
        var travelled = 0.0
        while !Task.isCancelled, queued == nil, let p = position {
            let dx = target.x - p.x, dy = target.y - p.y
            let distance = hypot(dx, dy)
            if distance <= speed * tick { position = target; break }
            pose.look = (dx >= 0) != backwards ? 1 : -1
            position = CGPoint(x: p.x + dx / distance * speed * tick, y: p.y + dy / distance * speed * tick)
            travelled += speed * tick
            pose.legs = Int(travelled / 6).isMultiple(of: 2) ? .left : .right
            try? await Task.sleep(for: .seconds(tick))
        }
        pose.legs = .stand
    }

    private func blink() async {
        pose.eyes = .blink
        try? await Task.sleep(for: .milliseconds(120))
        pose.eyes = .open
    }

    private func say(_ text: String, for seconds: Double = 2.4) {
        speechID += 1
        let id = speechID
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { speech = text }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if speechID == id { withAnimation(.easeOut(duration: 0.2)) { speech = nil } }
        }
    }

    private func perform(_ trick: ClawdTrick) async {
        pose.legs = .stand
        pose.look = 0
        switch trick {
        case .hop:
            say("Wheee!", for: 1.4)
            for _ in 0..<2 {
                pose.arms = .up
                withAnimation(.easeOut(duration: 0.18)) { hop = -24 }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeIn(duration: 0.18)) { hop = 0 }
                try? await Task.sleep(for: .milliseconds(200))
                pose.arms = .down
            }
        case .spin:
            withAnimation(.easeInOut(duration: 0.7)) { spin += 360 }
            try? await Task.sleep(for: .milliseconds(700))
            say("Ta-da!", for: 1.4)
            pose.arms = .up
            try? await Task.sleep(for: .milliseconds(600))
            pose.arms = .down
        case .wave:
            say("Hello!")
            for _ in 0..<3 {
                pose.arms = .up
                try? await Task.sleep(for: .milliseconds(250))
                pose.arms = .down
                try? await Task.sleep(for: .milliseconds(250))
            }
        case .dance:
            say("♪ ♫ ♪", for: 2)
            for i in 0..<8 {
                let even = i.isMultiple(of: 2)
                withAnimation(.easeInOut(duration: 0.16)) { tilt = even ? 12 : -12 }
                pose.legs = even ? .left : .right
                pose.arms = even ? .up : .down
                try? await Task.sleep(for: .milliseconds(200))
            }
            withAnimation(.easeInOut(duration: 0.16)) { tilt = 0 }
            pose = ClawdPose()
        case .talk:
            say(Self.phrases.randomElement()!)
            try? await Task.sleep(for: .seconds(1))
        case .love:
            say("♥")
            pose.eyes = .closed
            try? await Task.sleep(for: .seconds(1.2))
            pose.eyes = .open
        case .nap:
            pose.eyes = .closed
            say("Zzz…", for: 2.6)
            try? await Task.sleep(for: .seconds(2.8))
            pose.eyes = .open
            say("Huh?", for: 1.2)
            try? await Task.sleep(for: .seconds(1))
        case .backflip:
            say("Watch this!", for: 1)
            withAnimation(.easeOut(duration: 0.15)) { scale = 0.85 } // crouch
            try? await Task.sleep(for: .milliseconds(350))
            pose.arms = .up
            withAnimation(.easeOut(duration: 0.3)) { hop = -48; scale = 1 }
            withAnimation(.easeInOut(duration: 0.6)) { flip -= 360 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeIn(duration: 0.3)) { hop = 0 }
            try? await Task.sleep(for: .milliseconds(320))
            pose.arms = .down
            withAnimation(.spring(duration: 0.25, bounce: 0.6)) { scale = 0.9 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(duration: 0.25, bounce: 0.6)) { scale = 1 }
            say(["Nailed it!", "10/10", "Stuck the landing!"].randomElement()!, for: 1.6)
            pose.arms = .up
            try? await Task.sleep(for: .seconds(1))
        case .lol:
            say(["LOL", "LMAO", "hahaha", "XD"].randomElement()!, for: 2)
            pose.eyes = .closed
            for i in 0..<10 {
                withAnimation(.easeInOut(duration: 0.07)) { tilt = i.isMultiple(of: 2) ? 5 : -5; hop = i.isMultiple(of: 2) ? -3 : 0 }
                try? await Task.sleep(for: .milliseconds(90))
            }
            withAnimation(.easeOut(duration: 0.1)) { tilt = 0; hop = 0 }
            pose.eyes = .open
            say("…lol", for: 1.2)
            try? await Task.sleep(for: .seconds(1))
        case .zoomies:
            say("ZOOOOM!", for: 2.5)
            for _ in 0..<4 { await walk(to: randomSpot(), speed: 320) }
            say("*pant pant*", for: 1.5)
            try? await Task.sleep(for: .seconds(1.2))
        case .moonwalk:
            say("Hee-hee! ♪", for: 2.5)
            if let p = position {
                let target = clamped(CGPoint(x: p.x + (p.x > area.width / 2 ? -1 : 1) * 160, y: p.y))
                await walk(to: target, speed: 55, backwards: true)
            }
        case .faint:
            say("x_x", for: 2)
            pose.eyes = .closed
            withAnimation(.easeIn(duration: 0.35)) { tilt = [90, -90].randomElement()! }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.spring(duration: 0.4, bounce: 0.5)) { tilt = 0 }
            pose.eyes = .open
            say("I'm OK!", for: 1.4)
            try? await Task.sleep(for: .seconds(1))
        case .peekaboo:
            withAnimation(.easeIn(duration: 0.25)) { scale = 0.05 }
            try? await Task.sleep(for: .seconds(1.4))
            pose.arms = .up
            withAnimation(.spring(duration: 0.35, bounce: 0.6)) { scale = 1.15 }
            say("BOO!", for: 1.4)
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeOut(duration: 0.2)) { scale = 1 }
            try? await Task.sleep(for: .seconds(0.8))
        case .grow:
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { scale = 2.2 }
            say("I AM HUGE", for: 1.6)
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) { scale = 1 }
            say("…ok, normal", for: 1.2)
            try? await Task.sleep(for: .seconds(0.8))
        case .sneeze:
            say("Ah…", for: 0.6)
            try? await Task.sleep(for: .milliseconds(600))
            say("Ah…!", for: 0.6)
            pose.eyes = .blink
            withAnimation(.easeOut(duration: 0.3)) { tilt = -10 }
            try? await Task.sleep(for: .milliseconds(600))
            say("ACHOO!", for: 1.4)
            pose.eyes = .closed
            withAnimation(.spring(duration: 0.2, bounce: 0.5)) { tilt = 14; hop = -10 }
            if let p = position { withAnimation(.easeOut(duration: 0.25)) { position = clamped(CGPoint(x: p.x - 24, y: p.y)) } }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { tilt = 0; hop = 0 }
            pose.eyes = .open
            try? await Task.sleep(for: .seconds(1))
        case .dizzy:
            withAnimation(.easeIn(duration: 1.1)) { spin += 1080 }
            try? await Task.sleep(for: .milliseconds(1100))
            say("@_@", for: 2)
            for i in 0..<6 {
                withAnimation(.easeInOut(duration: 0.2)) { tilt = i.isMultiple(of: 2) ? 10 : -10 }
                try? await Task.sleep(for: .milliseconds(220))
            }
            withAnimation(.easeOut(duration: 0.2)) { tilt = 0 }
        case .error:
            say(["404: motivation not found", "Segmentation fault (core dumped)", "Rate limited. Try again later",
                 "Error: too many students"].randomElement()!, for: 2.2)
            for _ in 0..<6 {
                pose.eyes = pose.eyes == .open ? .closed : .open
                try? await Task.sleep(for: .milliseconds(120))
            }
            pose.eyes = .open
            try? await Task.sleep(for: .seconds(1.2))
            say("…rebooted", for: 1.2)
            try? await Task.sleep(for: .seconds(1))
        }
        withAnimation(.easeOut(duration: 0.15)) { tilt = 0; hop = 0; scale = 1 }
        pose.arms = .down
        pose.legs = .stand
    }
}

/// What Clawd does when clicked.
enum ClawdTrick: CaseIterable {
    case hop, spin, wave, dance, talk, love, nap
    case backflip, lol, zoomies, moonwalk, faint, peekaboo, grow, sneeze, dizzy, error

    /// A random trick, never the same one twice in a row.
    static func random(after last: ClawdTrick?) -> ClawdTrick {
        allCases.filter { $0 != last }.randomElement()!
    }
}

/// One frame of Clawd: its body is fixed, the arms, eyes and legs move.
struct ClawdPose: Equatable {
    enum Arms: CaseIterable { case down, up }
    enum Eyes: CaseIterable { case open, blink, closed }
    enum Legs: CaseIterable { case stand, left, right }

    var arms = Arms.down
    var eyes = Eyes.open
    var legs = Legs.stand
    /// Where the eyes look: -1 left, 0 ahead, 1 right.
    var look = 0

    static let width = 18, height = 10

    /// The frame as rows of pixels (true = ink), traced from Claude Code's terminal logo:
    /// a square body with two tall eyes, stubby arms out to the sides, four short legs.
    var pixels: [[Bool]] {
        var grid = Array(repeating: Array(repeating: false, count: Self.width), count: Self.height)
        func set(_ rows: ClosedRange<Int>, _ cols: ClosedRange<Int>, _ ink: Bool = true) {
            for r in rows { for c in cols { grid[r][c] = ink } }
        }
        set(0...7, 3...14)
        switch arms {
        case .down:
            set(4...5, 1...2); set(4...5, 15...16)
        case .up:
            set(4...4, 1...2); set(4...4, 15...16)
            set(2...3, 1...1); set(2...3, 16...16)
        }
        let look = max(-1, min(1, look))
        switch eyes {
        case .open: for eye in [5 + look, 12 + look] { set(2...3, eye...eye, false) }
        case .blink: for eye in [5 + look, 12 + look] { set(3...3, eye...eye, false) }
        case .closed: set(3...3, 4...5, false); set(3...3, 12...13, false)
        }
        let feet = [4, 6, 11, 13]
        for leg in feet { set(8...8, leg...leg) }
        let down = switch legs {
        case .stand: feet
        case .left: [4, 11]
        case .right: [6, 13]
        }
        for leg in down { set(9...9, leg...leg) }
        return grid
    }
}

/// Draws a pose in the text color, so Clawd is black in light mode and white in dark mode.
private struct ClawdSprite: View {
    let pose: ClawdPose
    static let pixel: CGFloat = 4

    var body: some View {
        let p = Self.pixel
        Canvas { context, _ in
            var path = Path()
            for (r, row) in pose.pixels.enumerated() {
                for (c, ink) in row.enumerated() where ink {
                    path.addRect(CGRect(x: CGFloat(c) * p, y: CGFloat(r) * p, width: p, height: p))
                }
            }
            context.fill(path, with: .foreground)
        }
        .frame(width: CGFloat(ClawdPose.width) * p, height: CGFloat(ClawdPose.height) * p)
    }
}

/// A square, pixel-style speech bubble with a stepped tail.
private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.background)
            .overlay(Rectangle().strokeBorder(.primary, lineWidth: 2))
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().frame(width: 6, height: 3)
                    Rectangle().frame(width: 3, height: 3)
                }
                .foregroundStyle(.primary)
                .offset(x: -4, y: 6)
            }
    }
}
