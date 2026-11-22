import AppKit
import SwiftUI

/// Who runs along a group's deadline track (D44): the student's own animal on their page, the cat on the group page.
enum DeadlineRunner: Equatable {
    case animal(String)
    case cat
}

/// The deadline countdown in the toolbar (D44): a short track from the group's start to a checkered flag,
/// with the runner at today's spot. The label shows on hover; a click shows the details and Edit Deadline….
/// Shows nothing when the group has no deadline.
struct DeadlinePill: View {
    let group: StudentGroup
    let runner: DeadlineRunner
    /// False while the student's animal is still running in from the title.
    var runnerVisible = true
    /// Where the runner sits on screen, so the run from the title can land on it.
    var runnerAnchor: ScreenAnchor?
    @State private var hovering = false
    @State private var showsDetails = false
    @State private var editing = false

    var body: some View {
        if let deadline = group.deadline {
            let countdown = Countdown(deadline: deadline, start: group.createdAt)
            let label = countdown.label(group.deadlineTitle)
            Button { showsDetails.toggle() } label: {
                HStack(spacing: 8) {
                    DeadlineTrack(countdown: countdown, runner: runner, runnerVisible: runnerVisible, anchor: runnerAnchor)
                    // Kept while the details are open: hiding it would narrow the pill and move the popover.
                    if hovering || showsDetails {
                        Text(label)
                            .monospacedDigit()
                            .foregroundStyle(countdown.isNear ? Color.orange : countdown.isPast ? Color.secondary : Color.primary)
                            .fixedSize()
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, 4)
            }
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
            .help(label)
            .accessibilityLabel(label)
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                DeadlineDetails(group: group, countdown: countdown) {
                    showsDetails = false
                    editing = true
                }
            }
            .sheet(isPresented: $editing) { DeadlineSheet(group: group) }
        }
    }
}

/// The track itself: the done part solid, the rest faint, orange in the last week.
struct DeadlineTrack: View {
    let countdown: Countdown
    let runner: DeadlineRunner
    let runnerVisible: Bool
    let anchor: ScreenAnchor?
    private let width: CGFloat = 76

    var body: some View {
        let tint: Color = countdown.isNear ? .orange : .primary
        ZStack(alignment: .bottomLeading) {
            Capsule().fill(.secondary.opacity(0.3)).frame(width: width, height: 3)
            Capsule().fill(tint.opacity(0.7)).frame(width: max(width * countdown.progress, 3), height: 3)
            CheckeredFlag().offset(x: width - 1)
            runnerView
        }
        .frame(width: width + 8, height: 24, alignment: .bottomLeading)
        .padding(.bottom, 2)
    }

    @ViewBuilder private var runnerView: some View {
        // Stops just before the flag, so the flag stays visible on the day and after it.
        let x = min(width * countdown.progress, width - 9)
        switch runner {
        case .animal(let emoji):
            ZStack {
                if runnerVisible {
                    // Mirrored, so it faces the flag.
                    Text(emoji).font(.system(size: 16)).scaleEffect(x: -1)
                }
            }
            .frame(width: 20, height: 20)
            .background { if let anchor { ScreenAnchorView(anchor: anchor) } }
            .offset(x: x - 10, y: -1)
        case .cat:
            WalkingCat(to: x, napping: countdown.isPast, cheering: countdown.days == 0)
        }
    }
}

/// The pixel cat (D38) walking from the start of the track to today's spot when the page opens.
private struct WalkingCat: View {
    let to: CGFloat
    let napping: Bool
    let cheering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var arrived = false
    private static let duration = 1.3
    private static let pixel: CGFloat = 0.5
    /// From the frame's left edge to the middle of the cat, and its rows below the feet.
    private static let center = CGFloat(CatPose.origin.x + 20) * pixel
    private static let below = CGFloat(CatPose.height - CatPose.groundRow - 1) * pixel

    var body: some View {
        TimelineView(.animation(paused: arrived || reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = arrived || reduceMotion ? 1 : min(elapsed / Self.duration, 1)
            CatSprite(pose: pose(walking: t < 1, elapsed: elapsed), pixel: Self.pixel)
                .offset(x: to * (1 - pow(1 - t, 2)) - Self.center, y: Self.below - 1)
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            arrived = true
        }
    }

    private func pose(walking: Bool, elapsed: Double) -> CatPose {
        var pose = CatPose()
        pose.facingRight = true
        if walking {
            pose.legs = [.left, .stand, .right, .stand][Int(elapsed / 0.11) % 4]
        } else if napping {
            pose.eyes = .sleep
            pose.legs = .tucked
            pose.tail = .wrapped
        } else if cheering {
            pose.eyes = .happy
        }
        return pose
    }
}

private struct CheckeredFlag: View {
    var body: some View {
        Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 1.5, height: 13)), with: .color(.secondary))
            for row in 0..<2 {
                for col in 0..<3 {
                    let rect = CGRect(x: 1.5 + CGFloat(col) * 2, y: CGFloat(row) * 2, width: 2, height: 2)
                    context.fill(Path(rect), with: .color((row + col).isMultiple(of: 2) ? .white : .black))
                }
            }
        }
        .frame(width: 8, height: 13)
    }
}

private struct DeadlineDetails: View {
    let group: StudentGroup
    let countdown: Countdown
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(group.name) · \(group.deadlineTitle)").font(.callout).foregroundStyle(.secondary)
            Text(countdown.headline)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(countdown.isNear ? Color.orange : Color.primary)
            VStack(spacing: 4) {
                row("Date", Text(group.deadline ?? .now, format: .dateTime.weekday().month().day().year()))
                row("Weekly sessions left", Text("\(countdown.sessionsLeft)"))
                row("Started", Text(group.createdAt, format: .dateTime.weekday().month().day()))
            }
            HStack {
                Spacer()
                Button("Edit Deadline…", action: onEdit)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, _ value: Text) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            value.monospacedDigit()
        }
    }
}

/// Sets, changes or removes the day every student of the group counts down to (D44).
struct DeadlineSheet: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let group: StudentGroup
    @State private var date: Date
    @State private var title: String
    @State private var error: String?

    init(group: StudentGroup) {
        self.group = group
        let inSixWeeks = WeekCalendar.calendar.date(byAdding: .weekOfYear, value: 6, to: WeekCalendar.calendar.startOfDay(for: .now))!
        _date = State(initialValue: group.deadline ?? inSixWeeks)
        _title = State(initialValue: group.deadline == nil ? "Demo day" : group.deadlineTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $title, prompt: Text("Demo day"))
                        .onSubmit { save(date) } // The focused field takes Return before the Save button.
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    LabeledContent("Countdown") {
                        Text(Countdown(deadline: date, start: group.createdAt).label(title.isEmpty ? "Demo day" : title))
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Every student in “\(group.name)” counts down to this day.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                if group.deadline != nil {
                    Button("Remove Deadline", role: .destructive) { save(nil) }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(date) }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 420)
    }

    private func save(_ date: Date?) {
        guard let id = group.id else { return }
        do {
            try db.setDeadline(groupId: id, date, title: title)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - The run from the title to the pill

/// A view's place on screen. Toolbar items are drawn apart from each other, so a view can't animate
/// from one to another inside SwiftUI; the run reads both places and draws in its own panel instead.
@MainActor final class ScreenAnchor {
    fileprivate weak var view: NSView?

    var window: NSWindow? { view?.window }
    var frame: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

struct ScreenAnchorView: NSViewRepresentable {
    let anchor: ScreenAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// The student's animal running from the title to its spot on the deadline track, in a clear panel
/// above the window that takes no clicks.
@MainActor enum RunnerFlight {
    /// Runs and calls `onLand` when it lands; returns false (and does nothing) when a place is unknown.
    /// `clear` is how far the first leap goes to get over the name next to the animal.
    @discardableResult
    static func run(_ emoji: String, style: RunnerStyle, speed: Double, from: ScreenAnchor, to: ScreenAnchor,
                    fromSize: CGFloat, toSize: CGFloat, clear: CGFloat,
                    onLand: @escaping @MainActor () -> Void) -> Bool {
        guard let window = from.window, let a = from.frame, let b = to.frame else { return false }
        // The run stays inside the window, so the panel does too: macOS moves a panel that reaches under the menu bar.
        let area = a.union(b).insetBy(dx: -40, dy: -40).intersection(window.frame)
        let panel = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        window.addChildWindow(panel, ordered: .above)

        // Measured from where the panel really is. Its origin is at the top left; the screen's is at the bottom left.
        let frame = panel.frame
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y) }
        // The leap over the name goes as high as the window's top edge lets it.
        let headroom = window.frame.maxY - a.midY - fromSize / 2 - 2
        let path = RunnerPath(style: style, from: local(CGPoint(x: a.midX, y: a.midY)), to: local(CGPoint(x: b.midX, y: b.midY)),
                              fromSize: fromSize, toSize: toSize, clear: clear, leap: min(max(headroom, 8), 18), speed: speed)
        panel.contentView = NSHostingView(rootView: RunnerFlightView(emoji: emoji, path: path, start: .now)
            .frame(width: frame.width, height: frame.height))

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(path.duration))
            onLand()
            // One more frame, so the animal on the track is drawn before the flying one goes.
            try? await Task.sleep(for: .milliseconds(50))
            window.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        return true
    }
}

/// Draws a `RunnerPath` from `start` on: the animal, the dust at its feet and the dash's speed lines.
struct RunnerFlightView: View {
    let emoji: String
    let path: RunnerPath
    let start: Date
    private static let puffTime = 0.35

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince(start)
            let pose = path.pose(at: time)
            ZStack {
                ForEach(Array(path.puffs.enumerated()), id: \.offset) { _, puff in
                    let age = (time - puff.time) / Self.puffTime
                    if age >= 0, age < 1 {
                        Circle().fill(.secondary.opacity(0.7 * (1 - age)))
                            .frame(width: 6, height: 6)
                            .scaleEffect(0.6 + age)
                            .position(x: puff.point.x - 4 - 10 * age, y: puff.point.y - 3 - 4 * age)
                    }
                }
                if pose.speed > 0.05 {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(.secondary.opacity(pose.speed * (1 - Double(i) * 0.25)))
                            .frame(width: 14, height: 2)
                            .position(x: pose.center.x - pose.size / 2 - 12 - CGFloat(i) * 9,
                                      y: pose.center.y + pose.size / 2 - 5 - CGFloat(i) * 4)
                    }
                }
                RunnerSprite(emoji: emoji, pose: pose)
            }
        }
    }
}

private struct RunnerSprite: View {
    let emoji: String
    let pose: RunnerPath.Pose

    var body: some View {
        Text(emoji)
            .font(.system(size: pose.size))
            .fixedSize()
            // Mirrored to face the flag; squashed on the ground and stretched in the air.
            .scaleEffect(x: (pose.facesFlag ? -1 : 1) * pose.stretch.width, y: pose.stretch.height, anchor: .bottom)
            .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
            .position(pose.center)
    }
}

/// A small copy of the run for Settings: it plays again when the style or the speed changes.
struct RunnerPreview: View {
    let style: RunnerStyle
    let speed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var landed = false
    /// A track that is half done, so the runner's spot is in the middle.
    private static let halfway = Countdown(deadline: .now.addingTimeInterval(42 * 86_400), start: .now.addingTimeInterval(-42 * 86_400))

    var body: some View {
        GeometryReader { geometry in
            let middle = geometry.size.height / 2
            // The animal starts where the title's emoji would be and lands on the runner's spot of the track.
            let path = RunnerPath(style: style, from: CGPoint(x: 11, y: middle),
                                  to: CGPoint(x: geometry.size.width - 74, y: middle),
                                  fromSize: 22, toSize: 16, clear: 130, speed: speed)
            HStack(spacing: 8) {
                Color.clear.frame(width: 22, height: 22)
                Text("Student name").font(.headline)
                Spacer()
                DeadlineTrack(countdown: Self.halfway, runner: .animal(""), runnerVisible: false, anchor: nil)
                Button("Play", systemImage: "play.fill", action: play)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 20)
                    .help("Play the run again")
            }
            .frame(maxHeight: .infinity)
            // Drawn over the row; clicks go through to the Play button.
            Group {
                if let start, !landed, !reduceMotion {
                    RunnerFlightView(emoji: "🐥", path: path, start: start)
                } else {
                    RunnerSprite(emoji: "🐥", pose: path.pose(at: landed ? path.duration : 0))
                }
            }
            .allowsHitTesting(false)
            .task(id: start) {
                guard start != nil else { return }
                try? await Task.sleep(for: .seconds(path.duration + 0.1))
                if !Task.isCancelled { landed = true }
            }
        }
        .frame(height: 52)
        .onChange(of: style) { play() }
        .onChange(of: speed) { play() }
    }

    private func play() {
        landed = false
        start = .now
    }
}
