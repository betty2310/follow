import SwiftUI

/// The cat from the app icon as pixel art, wandering the detail pane (D38).
/// Students report about once a week, so most days are blank; the cat keeps them company.
/// It lives above the student and group pages, so switching pages doesn't move or reset it.
/// It walks to random spots, blinks and says things now and then; click it for a random trick,
/// right-click to hide it (Settings brings it back).
struct CatPlayground: View {
    @AppStorage("cat.visible") private var visible = true
    @AppStorage("cat.size") private var catSize = CatSprite.defaultSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var area: CGSize = .zero
    @State private var position: CGPoint?
    @State private var pose = CatPose()
    @State private var speech: String?
    @State private var speechID = 0
    @State private var queued: CatTrick?
    @State private var lastTrick: CatTrick?

    static var phrases: [String] {
        [
            "Meow", "Mrrp?", "Purr…", "Hello!", "Who's next?", "Any notes today?", "Did they report yet?",
            "Nice week!", "Keep going!", "Hmm…", "I like this project", "Snack?", "Nap time?",
            "I'll take the notes", "*stretches*", "*yawns*", "Week \(WeekCalendar.week(of: .now).week) already?!",
        ]
    }

    var body: some View {
        if visible {
            // Color.clear takes no clicks, so the board under it stays usable; only the cat does.
            Color.clear
                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                    area = size
                    position = position.map(clamped)
                }
                .overlay(alignment: .topLeading) {
                    if let position { cat.offset(x: position.x - size.width / 2, y: position.y - feet) }
                }
                .onChange(of: catSize) { position = position.map(clamped) }
                .task { await live() }
        }
    }

    /// Points per pixel, from Settings → Fun.
    private var pixel: CGFloat { CGFloat(catSize) }
    private var size: CGSize { CGSize(width: CGFloat(CatPose.width) * pixel, height: CGFloat(CatPose.height) * pixel) }
    /// From the top of the frame to the bottom of the feet; `position` is the feet.
    private var feet: CGFloat { CGFloat(CatPose.groundRow + 2) * pixel }
    /// The cat itself, the part that takes clicks; it is centered, so it stays put when the cat turns.
    private var hitBox: CGRect {
        CGRect(x: (CGFloat(CatPose.width) / 2 - 17) * pixel, y: CGFloat(CatPose.origin.y + 2) * pixel,
               width: 34 * pixel, height: 21 * pixel)
    }

    private var cat: some View {
        CatSprite(pose: pose, pixel: pixel)
            .offset(y: -CGFloat(pose.lift) * pixel)
            .overlay(alignment: .bottom) {
                if let speech {
                    SpeechBubble(text: speech)
                        .fixedSize()
                        .offset(y: -(size.height - CGFloat(CatPose.origin.y) * pixel))
                        .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Path(hitBox))
            .onTapGesture { queued = CatTrick.random(after: lastTrick) }
            .pointerStyle(.link)
            .contextMenu {
                Button("Hide Cat") { visible = false }
            }
            .accessibilityElement()
            .accessibilityLabel("Cat")
            .accessibilityAddTraits(.isButton)
            .transition(.opacity)
    }

    // MARK: Behavior

    /// The whole pane, less a margin; the top keeps room for a speech bubble.
    private var walkArea: CGRect {
        let minX = size.width / 2 + 4, minY = feet + 20
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
            } else if !reduceMotion, Double.random(in: 0..<1) < 0.1 {
                // Now and then a trick on its own, nobody asked.
                let trick = CatTrick.random(after: lastTrick)
                lastTrick = trick
                await perform(trick)
            } else if !reduceMotion, Double.random(in: 0..<1) < 0.75 {
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

    /// Walks in a straight line at `speed` points per second.
    private func walk(to target: CGPoint, speed: Double = .random(in: 45...75)) async {
        let tick = 1.0 / 30
        var travelled = 0.0
        pose.look = 0
        while !Task.isCancelled, queued == nil, let p = position {
            let dx = target.x - p.x, dy = target.y - p.y
            let distance = hypot(dx, dy)
            if distance <= speed * tick { position = target; break }
            pose.facingRight = dx >= 0
            position = CGPoint(x: p.x + dx / distance * speed * tick, y: p.y + dy / distance * speed * tick)
            travelled += speed * tick
            pose.legs = Int(travelled / 6).isMultiple(of: 2) ? .left : .right
            pose.bob = pose.legs == .left ? 1 : 0
            pose.sway = sin(travelled / 12) * 0.5
            try? await Task.sleep(for: .seconds(tick))
        }
        pose.legs = .stand
        pose.bob = 0
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

    /// Plays a trick's frames for its duration, keeping the way the cat faces.
    private func play(_ trick: CatTrick) async {
        let start = ContinuousClock.now
        while !Task.isCancelled {
            let t = (ContinuousClock.now - start) / .seconds(1)
            if t >= trick.duration { break }
            var next = trick.pose(at: t)
            next.facingRight = pose.facingRight
            pose = next
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func perform(_ trick: CatTrick) async {
        pose = CatPose(facingRight: pose.facingRight)
        // Words that would cover a floating prop (Zzz, ♪, ✓, ♥) come after the trick.
        var after: String?
        switch trick {
        case .zoomies:
            say("ZOOOOM!", for: 2.5)
            for _ in 0..<4 { await walk(to: randomSpot(), speed: 320) }
            after = "*pant pant*"
        case .nap: after = "Huh?"
        case .notes: say("Taking notes…", for: 3)
        case .listen: after = "♪"
        case .checkIn: after = "Checked in!"
        case .stretch: say("Mrrrow…", for: 2.4)
        case .groom: say("*lick lick*", for: 2)
        case .happy: after = "Purr!"
        case .loaf: break
        }
        if trick != .zoomies { await play(trick) }
        pose = CatPose(facingRight: pose.facingRight)
        if let after {
            say(after, for: 1.4)
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// What the cat does when clicked, and now and then on its own.
enum CatTrick: CaseIterable {
    case nap, notes, listen, checkIn, stretch, groom, happy, loaf, zoomies

    /// A random trick, never the same one twice in a row.
    static func random(after last: CatTrick?) -> CatTrick {
        allCases.filter { $0 != last }.randomElement()!
    }

    /// Seconds the trick plays; zoomies is a few fast walks instead.
    var duration: Double {
        switch self {
        case .nap: 4.2
        case .notes: 5
        case .listen: 3.5
        case .checkIn: 2.6
        case .stretch: 3.6
        case .groom: 2.6
        case .happy: 2.8
        case .loaf: 3.5
        case .zoomies: 0
        }
    }

    /// The frame `t` seconds into the trick.
    func pose(at t: Double) -> CatPose {
        func every(_ seconds: Double) -> Bool { Int(t / seconds).isMultiple(of: 2) }
        switch self {
        case .nap:
            return CatPose(legs: .tucked, eyes: .sleep, mouth: .none, tail: .wrapped, bob: every(1.4) ? 0 : 1, prop: .zzz(t))
        case .notes:
            return CatPose(legs: .tucked, eyes: t.truncatingRemainder(dividingBy: 3.2) > 2.9 ? .blink : .open,
                           look: -1, sway: sin(t * 2) * 0.4, prop: .clipboard(t))
        case .listen:
            let beat = every(0.42) ? 0 : 1
            return CatPose(legs: .tucked, eyes: .closed, sway: beat == 1 ? 0.8 : -0.4, frontDrop: beat, prop: .headphones(t))
        case .checkIn:
            // Crouch, hop up with a check mark, land, look pleased.
            var pose = CatPose(eyes: .happy, sway: 1)
            if t < 0.2 || (t >= 0.7 && t < 0.82) { pose.squash = -1; pose.eyes = .open }
            if t >= 0.2, t < 0.7 {
                pose.lift = Int((sin((t - 0.2) / 0.5 * .pi) * 9).rounded())
                pose.squash = 1
                if pose.lift > 2 { pose.legs = .left }
            }
            if t > 0.55 { pose.prop = .check(rise: min(2, Int(((t - 0.55) * 4).rounded()))) }
            return pose
        case .stretch:
            if t < 0.4 || t > 3.2 { return CatPose() }
            let hold = t > 0.7 && t < 2.9
            return CatPose(legs: .reach, eyes: .closed, mouth: t > 1.2 && t < 2.4 ? .yawn : .smile,
                           sway: 1, frontDrop: hold ? 3 : 1, rearDrop: hold ? -1 : 0)
        case .groom:
            let up = !every(0.3)
            return CatPose(legs: .tucked, eyes: .closed, mouth: up ? .lick : .smile, sway: sin(t) * 0.5, prop: .paw(up: up))
        case .happy:
            let c = t.truncatingRemainder(dividingBy: 0.7)
            return CatPose(eyes: .happy, sway: sin(t * 14), squash: c < 0.1 ? -1 : 0,
                           lift: c > 0.1 && c < 0.45 ? 2 : 0, prop: .heart(t))
        case .loaf:
            let c = t.truncatingRemainder(dividingBy: 5)
            return CatPose(legs: .tucked, eyes: c > 2 && c < 2.9 ? .closed : .open, tail: .wrapped)
        case .zoomies:
            return CatPose()
        }
    }
}

/// The colors of the cat and its props, after the app icon.
enum CatInk: Hashable {
    case line, fur, ear, mouth, wood, paper, gray, check, record, pencil, cup, heart

    init?(glyph: Character) {
        switch glyph {
        case "#": self = .line
        case ".": self = .fur
        case "G": self = .check
        case "H": self = .heart
        case "R": self = .record
        case "O": self = .cup
        default: return nil
        }
    }

    var color: Color {
        func rgb(_ hex: UInt32) -> Color {
            Color(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
        }
        return switch self {
        case .line: rgb(0x1d1d1f)
        case .fur, .paper: rgb(0xffffff)
        case .ear: rgb(0xffb3c0)
        case .mouth: rgb(0xe2566e)
        case .wood: rgb(0xb5793f)
        case .gray: rgb(0xa6a6a6)
        case .check: rgb(0x2f9e44)
        case .record: rgb(0xef3b3b)
        case .pencil: rgb(0xf4b62c)
        case .cup: rgb(0xff7a59)
        case .heart: rgb(0xef4565)
        }
    }
}

/// One frame of the cat. The body is built from two rounded blobs (head end and rump), two ear
/// triangles, a tail and four feet, then outlined; the pose moves those parts and adds a prop.
struct CatPose: Equatable {
    enum Legs: CaseIterable { case stand, left, right, tucked, reach }
    enum Eyes: CaseIterable { case open, blink, closed, happy, sleep }
    enum Mouth: CaseIterable { case smile, yawn, lick, none }
    enum Tail: CaseIterable { case up, wrapped }
    /// Something the cat holds or that floats around it; the Double is seconds into the trick.
    enum Prop: Equatable {
        case none, zzz(Double), clipboard(Double), headphones(Double), check(rise: Int), heart(Double), paw(up: Bool)
    }

    var legs = Legs.stand
    var eyes = Eyes.open
    var mouth = Mouth.smile
    var tail = Tail.up
    /// Where the eyes look: -1 forward (toward the head end), 0 ahead, 1 back.
    var look = 0
    /// The tail's swing, -1...1.
    var sway = 0.0
    /// Rows the head end and the rump sink (negative rises).
    var frontDrop = 0
    var rearDrop = 0
    /// Rows the body rises off its feet (a step).
    var bob = 0
    /// Rows the body gets taller (positive) or flatter (negative).
    var squash = 0
    /// Rows the whole cat is off the ground (a hop); the view applies it.
    var lift = 0
    var facingRight = false
    var prop = Prop.none

    static let width = 63, height = 36
    /// Where the cat's own 40 × 24 drawing (facing left) sits in the frame; the margin holds the props.
    /// The frame is centered on the cat, tail included, so turning around mirrors it in place.
    static let origin = (x: 12, y: 12)
    private static let ground = 21
    /// The row the feet stand on.
    static let groundRow = origin.y + ground

    private static let ears: [(x0: Double, x1: Double, apexX: Double, baseY: Double, apexY: Double)] =
        [(5, 10, 6.5, 9, 3), (14, 19, 16.5, 8, 3)]
    private static let smallZ = ["###", " # ", "###"]
    private static let bigZ = ["###", "  #", " # ", "#  ", "###"]
    private static let checkMark = ["     ##", "    #G#", "#  #G# ", "#G#G#  ", " #G#   ", "  #    "]
    private static let heartShape = [" ## ## ", "#HH#HH#", "#HHHHH#", " #HHH# ", "  #H#  ", "   #   "]
    private static let note = [" ###", " # #", " # #", "## #", "## "]
    private static let paw = [" ### ", "#...#", "#...#", " ### "]
    private static let cup = ["####", "#OO#", "#OO#", "#OO#", "####"]
    private static let recordDot = [" RR ", "RRRR", "RRRR", " RR "]

    /// The frame as rows of pixels, nil where it's empty.
    var pixels: [[CatInk?]] {
        let W = Self.width, H = Self.height, ox = Self.origin.x, oy = Self.origin.y, g = Double(Self.ground)
        var fill = Array(repeating: Array(repeating: false, count: W), count: H)
        // Drawing happens in the cat's own coordinates, facing left.
        func set(_ x: Double, _ y: Double) {
            let gx = Int(x.rounded()) + ox, gy = Int(y.rounded()) + oy
            if gx >= 0, gy >= 0, gx < W, gy < H { fill[gy][gx] = true }
        }
        let rise = Double((legs == .tucked ? 1 : 0) - bob)
        let front = rise + Double(frontDrop), rear = rise + Double(rearDrop), s = Double(squash)

        func blob(cx: Double, cy: Double, rx: Double, ry: Double, n: Double, drop: Double) {
            let ry = ry + s, rx = rx - s * 0.6, cy = cy + drop - s
            for gy in 0..<H where Double(gy - oy) <= g {
                let y = Double(gy - oy)
                for gx in 0..<W {
                    let u = abs((Double(gx - ox) + 0.5 - cx) / rx), w = abs((y + 0.5 - cy) / ry)
                    if pow(u, n) + pow(w, n) <= 1 { fill[gy][gx] = true }
                }
            }
        }
        blob(cx: 21.5, cy: 13.6, rx: 10, ry: 6.7, n: 2.6, drop: rear)
        blob(cx: 12.5, cy: 13, rx: 9, ry: 7.3, n: 2.2, drop: front)
        let body = fill

        var earPixels: [(x: Int, y: Int)] = []
        for ear in Self.ears {
            let a = (ear.x0, ear.baseY + front), b = (ear.x1 + 1, ear.baseY + front), c = (ear.apexX + 0.5, ear.apexY + front)
            func side(_ p: (Double, Double), _ q: (Double, Double), _ r: (Double, Double)) -> Double {
                (p.0 - r.0) * (q.1 - r.1) - (q.0 - r.0) * (p.1 - r.1)
            }
            for gy in 0..<H {
                for gx in 0..<W {
                    let p = (Double(gx - ox) + 0.5, Double(gy - oy) + 0.5)
                    let d = [side(p, a, b), side(p, b, c), side(p, c, a)]
                    guard !(d.contains(where: { $0 < 0 }) && d.contains(where: { $0 > 0 })) else { continue }
                    fill[gy][gx] = true
                    if !body[gy][gx] { earPixels.append((gx, gy)) }
                }
            }
        }

        // The tail is a 1-pixel curve; the outline makes it three wide.
        var (x, y, angle, curl): (Double, Double, Double, Double) = switch tail {
        case .up: (31, 14 + rear, -15 + sway * 25, -75 + sway * 10)
        case .wrapped: (30, g - 1, 0, -30)
        }
        var tailPoints: [(Double, Double)] = []
        for i in 0...18 {
            tailPoints.append((x, y))
            let a = (angle + curl * Double(i) / 3 / 6 * 1.6) * .pi / 180
            x += cos(a) / 3
            y += sin(a) / 3
        }
        for p in tailPoints { set(p.0, p.1) }
        if tail == .up {
            let end = tailPoints[tailPoints.count - 1]
            set(end.0 + 1, end.1); set(end.0, end.1 - 1); set(end.0 + 1, end.1 - 1)
        }

        if legs != .tucked {
            for (i, fx) in [7.0, 11, 22, 26].enumerated() {
                let isFront = i < 2
                let up = (legs == .left && (i == 0 || i == 3)) || (legs == .right && (i == 1 || i == 2))
                let x0 = legs == .reach && isFront ? fx - 4 : fx
                let bottom = up ? g - 1 : g
                for y in stride(from: bottom - 2, through: bottom, by: 1) { set(x0, y); set(x0 + 1, y) }
                if legs == .reach && isFront { for k in 0..<5 { set(x0 + Double(k), g) } }
            }
        }

        // Outline: every empty pixel that touches the cat.
        func filled(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && fill[y][x] }
        var grid = Array(repeating: [CatInk?](repeating: nil, count: W), count: H)
        for gy in 0..<H {
            for gx in 0..<W {
                if fill[gy][gx] { grid[gy][gx] = .fur }
                else if filled(gx + 1, gy) || filled(gx - 1, gy) || filled(gx, gy + 1) || filled(gx, gy - 1) { grid[gy][gx] = .line }
            }
        }
        for p in earPixels where filled(p.x + 1, p.y) && filled(p.x - 1, p.y) && filled(p.x, p.y + 1) && filled(p.x, p.y - 1) {
            grid[p.y][p.x] = .ear
        }

        // Face, drawn only on the cat.
        func ink(_ x: Double, _ y: Double, _ c: CatInk = .line) {
            let gx = Int(x.rounded()) + ox, gy = Int(y.rounded()) + oy
            if gx >= 0, gy >= 0, gx < W, gy < H, grid[gy][gx] != nil { grid[gy][gx] = c }
        }
        let eyeY = 12 + front, look = Double(max(-1, min(1, look)))
        for eye in [9.0, 15] {
            let ex = eye + look
            switch eyes {
            case .open: ink(ex, eyeY)
            case .blink: ink(ex, eyeY); ink(ex + 1, eyeY)
            case .closed: ink(ex - 1, eyeY); ink(ex, eyeY)
            case .happy: ink(ex - 1, eyeY + 1); ink(ex, eyeY); ink(ex + 1, eyeY + 1)
            case .sleep: ink(ex - 1, eyeY); ink(ex, eyeY + 1); ink(ex + 1, eyeY)
            }
        }
        let mx = 12 + look, my = eyeY + 2
        switch mouth {
        case .smile: // ω
            ink(mx - 2, my); ink(mx - 1, my + 1); ink(mx, my); ink(mx + 1, my + 1); ink(mx + 2, my)
        case .yawn:
            ink(mx - 1, my); ink(mx, my); ink(mx + 1, my)
            for k in 1...2 { ink(mx - 1, my + Double(k)); ink(mx, my + Double(k), .mouth); ink(mx + 1, my + Double(k)) }
            ink(mx, my + 3)
        case .lick:
            ink(mx - 1, my); ink(mx + 1, my); ink(mx, my + 1, .mouth)
        case .none: break
        }

        if facingRight { grid = grid.map { Array($0.reversed()) } }

        // Props go on top, mirrored with the cat.
        func put(_ x: Double, _ y: Double, _ c: CatInk) {
            var gx = Int(x.rounded()) + ox
            let gy = Int(y.rounded()) + oy
            if facingRight { gx = W - 1 - gx }
            if gx >= 0, gy >= 0, gx < W, gy < H { grid[gy][gx] = c }
        }
        /// `readable` keeps letters and symbols the right way round when the cat faces right.
        func glyph(_ rows: [String], _ x: Double, _ y: Double, readable: Bool = false) {
            let width = rows.map(\.count).max() ?? 0
            for (r, row) in rows.enumerated() {
                for (k, ch) in row.enumerated() {
                    guard let c = CatInk(glyph: ch) else { continue }
                    let col = facingRight && readable ? width - 1 - k : k
                    put(x + Double(col), y + Double(r), c)
                }
            }
        }
        func cycle(_ t: Double, _ period: Double) -> Double { t.truncatingRemainder(dividingBy: period) }
        let headTop = 3.0, rightEar = 16.5

        switch prop {
        case .none: break
        case .zzz(let t):
            for i in 0..<3 {
                let ph = cycle(t * 0.45 + Double(i) / 3, 1)
                glyph(ph > 0.5 ? Self.bigZ : Self.smallZ, rightEar + 2 + (ph * 6).rounded(),
                      headTop + front - 1 - (ph * 9).rounded(), readable: true)
            }
        case .clipboard(let t):
            // A clipboard on the floor; lines get written one by one, then a check, then a fresh sheet.
            let x0 = -10.0, w = 13, h = 8, y0 = g - Double(h) + 1
            for r in 0..<h {
                for k in 0..<w {
                    let edge = r == 0 || k == 0 || r == h - 1 || k == w - 1
                    let rim = r == 1 || k == 1 || r == h - 2 || k == w - 2
                    put(x0 + Double(k), y0 + Double(r), edge ? .line : rim ? .wood : .paper)
                }
            }
            let clip = x0 + Double(w / 2) - 1
            put(clip, y0, .gray); put(clip + 1, y0, .gray); put(clip, y0 - 1, .line); put(clip + 1, y0 - 1, .line)
            let rows = [y0 + 2, y0 + 4], lineWidth = w - 5
            let c = cycle(t, Double(rows.count) * 1.1 + 1.6), written = min(rows.count, Int(c / 1.1))
            for (i, y) in rows.prefix(written).enumerated() {
                for k in 0..<(i == rows.count - 1 ? lineWidth - 2 : lineWidth) { put(x0 + 2 + Double(k), y, .gray) }
            }
            var tip: (x: Double, y: Double)
            if written < rows.count {
                let y = rows[written], length = Int(cycle(c, 1.1) / 1.1 * Double(lineWidth))
                for k in 0..<length { put(x0 + 2 + Double(k), y, .gray) }
                tip = (x0 + 2 + Double(length), y - Double(Int(t * 10) % 2))
            } else {
                let y = rows[rows.count - 1], right = x0 + Double(w)
                put(right - 4, y, .check); put(right - 3, y - 1, .check); put(right - 5, y - 1, .check)
                tip = (right - 2, y0 - 1)
            }
            put(tip.x, tip.y, .line)
            for k in 1...3 { put(tip.x + Double(k), tip.y - Double(k), .pencil) }
            put(tip.x + 4, tip.y - 4, .ear)
            glyph(Self.paw, tip.x + 1, tip.y - 4)
            if cycle(t, 1) < 0.6 { glyph(Self.recordDot, x0 - 1, y0 - 6) }
        case .headphones(let t):
            let left = 3.0, right = 21.0, top = 11 + front, peak = headTop - 1 + front, cx = 12.0, rx = 9.0
            var previous: Double?
            for x in stride(from: left, through: right, by: 1) {
                let y = (top - (top - peak) * max(0, 1 - pow((x - cx) / rx, 2)).squareRoot()).rounded()
                if let previous {
                    for yy in stride(from: min(previous, y), through: max(previous, y), by: 1) {
                        put(yy == y || y < previous ? x : x - 1, yy, .line)
                    }
                }
                put(x, y, .line)
                previous = y
            }
            glyph(Self.cup, left - 2, top)
            glyph(Self.cup, right - 1, top)
            let ph = cycle(t * 0.6, 1)
            glyph(Self.note, rightEar + 4 + (ph * 4).rounded(), headTop - 2 - (ph * 7).rounded(), readable: true)
        case .check(let rise):
            glyph(Self.checkMark, 10, headTop + front - 8 - Double(rise), readable: true)
        case .heart(let t):
            let ph = cycle(t * 0.55, 1)
            if ph < 0.85 { glyph(Self.heartShape, rightEar + 1, headTop + front - 8 - (ph * 6).rounded(), readable: true) }
        case .paw(let up):
            let u = up ? 1.0 : 0
            glyph(Self.paw, mx - 6 + u, my - u)
        }
        return grid
    }
}

/// Draws a pose as pixels in the cat's own colors, so it looks like the app icon in light and dark mode.
struct CatSprite: View {
    let pose: CatPose
    /// Points per pixel.
    let pixel: CGFloat

    /// The sizes Settings offers, in points per pixel; whole numbers keep the pixels crisp.
    static let sizes: ClosedRange<Double> = 2...6
    static let defaultSize = 3.0

    var body: some View {
        let p = pixel
        Canvas { context, _ in
            var paths: [CatInk: Path] = [:]
            for (r, row) in pose.pixels.enumerated() {
                for (c, ink) in row.enumerated() {
                    if let ink { paths[ink, default: Path()].addRect(CGRect(x: CGFloat(c) * p, y: CGFloat(r) * p, width: p, height: p)) }
                }
            }
            for (ink, path) in paths { context.fill(path, with: .color(ink.color)) }
        }
        .frame(width: CGFloat(CatPose.width) * p, height: CGFloat(CatPose.height) * p)
    }
}

/// The cat idling at a given size, for Settings: it blinks, looks around and swings its tail.
/// The view is cropped to the cat, so its height follows the size.
struct CatPreview: View {
    let pixel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows from the tips of the ears to the bottom of the feet.
    private static let rows = CatPose.groundRow + 2 - CatPose.origin.y

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            CatSprite(pose: reduceMotion ? CatPose() : Self.pose(at: context.date.timeIntervalSinceReferenceDate), pixel: pixel)
                // The frame has one empty row under the feet.
                .offset(y: pixel)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: CGFloat(Self.rows) * pixel, alignment: .bottom)
        .clipped()
        .padding(.bottom, 4)
        .accessibilityElement()
        .accessibilityLabel("Cat preview")
    }

    private static func pose(at t: Double) -> CatPose {
        let blink = t.truncatingRemainder(dividingBy: 3.2) > 3.05
        let look = [0, -1, 0, 1][Int(t / 2) % 4]
        return CatPose(eyes: blink ? .blink : .open, look: look, sway: sin(t * 2) * 0.6)
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
