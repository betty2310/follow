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
private struct DeadlineTrack: View {
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
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
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

/// The student's animal hopping from the title to its spot on the deadline track, in a clear panel
/// above the window that takes no clicks.
@MainActor enum RunnerFlight {
    /// Runs and calls `onLand` when it lands; returns false (and does nothing) when a place is unknown.
    @discardableResult
    static func run(_ emoji: String, from: ScreenAnchor, to: ScreenAnchor, fromSize: CGFloat, toSize: CGFloat,
                    onLand: @escaping @MainActor () -> Void) -> Bool {
        guard let window = from.window, let a = from.frame, let b = to.frame else { return false }
        let area = a.union(b).insetBy(dx: -40, dy: -40)
        // Panel coordinates have their origin at the top left; the screen's is at the bottom left.
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - area.minX, y: area.maxY - p.y) }
        let start = local(CGPoint(x: a.midX, y: a.midY)), end = local(CGPoint(x: b.midX, y: b.midY))
        let duration = min(0.45 + hypot(end.x - start.x, end.y - start.y) * 0.0008, 1.0)

        let panel = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: FlightView(
            emoji: emoji, from: start, to: end, fromSize: fromSize, toSize: toSize, start: .now, duration: duration)
            .frame(width: area.width, height: area.height))
        window.addChildWindow(panel, ordered: .above)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            onLand()
            // One more frame, so the animal on the track is drawn before the flying one goes.
            try? await Task.sleep(for: .milliseconds(50))
            window.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        return true
    }
}

private struct FlightView: View {
    let emoji: String
    let from: CGPoint
    let to: CGPoint
    let fromSize: CGFloat
    let toSize: CGFloat
    let start: Date
    let duration: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = min(max(context.date.timeIntervalSince(start) / duration, 0), 1)
            let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            let straight = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e)
            // It drops to a runway just under the name, so it doesn't cover the title, yet stays above the
            // toolbar's bottom edge; then it hops up onto the track.
            let runway = max(from.y, to.y) + 5
            let dip = (runway - straight.y) * min(1, sin(.pi * e) * 1.6)
            let strides = max(3, Int((hypot(to.x - from.x, to.y - from.y) / 70).rounded()))
            let phase = t * Double(strides)
            let hop = abs(sin(.pi * phase)) * 6 * (1 - t * 0.4)
            let onGround = abs(sin(.pi * phase)) < 0.18 || t == 1
            Text(emoji)
                .font(.system(size: fromSize + (toSize - fromSize) * e))
                .fixedSize()
                // Mirrored to face the flag; squashed on each landing and stretched in the air.
                .scaleEffect(x: onGround ? -1.12 : -0.95, y: onGround ? 0.86 : 1.06, anchor: .bottom)
                .rotationEffect(.degrees(onGround ? 0 : 8), anchor: .bottom)
                .position(x: straight.x, y: straight.y + dip - hop)
        }
    }
}
