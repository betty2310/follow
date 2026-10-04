import SwiftUI

/// Sidebar-driven layout (docs/DECISIONS.md D17, D25, D26): search on top, then every group as a
/// collapsible row with its students, and archived groups in their own section. Selecting a group shows its dashboard.
/// Settings live in the Settings window (⌘,).
enum SidebarItem: Hashable {
    case group(Int64)
    case student(Int64)
}

struct ContentView: View {
    @Environment(\.appDatabase) private var db
    @State private var groups: [GroupProgress] = []
    @State private var selection: SidebarItem?
    @State private var search = ""
    @State private var importing = false
    @State private var naming: GroupNaming?
    @State private var nameDraft = ""
    @State private var deleting: GroupProgress?
    @State private var error: String?
    /// Comma-separated ids of groups whose students are hidden.
    @AppStorage("sidebar.collapsedGroups") private var collapsedRaw = ""
    @AppStorage("sidebar.showArchived") private var showArchived = false

    private var active: [GroupProgress] { groups.filter { !$0.group.isArchived } }
    private var archived: [GroupProgress] { groups.filter { $0.group.isArchived } }

    /// The group the selection belongs to: the selected group, or the selected student's group.
    private var currentGroup: GroupProgress? {
        switch selection {
        case .group(let id): groups.first { $0.id == id }
        case .student(let id): groups.first { $0.students.contains { $0.id == id } }
        case nil: nil
        }
    }

    private var collapsed: Set<Int64> { Set(collapsedRaw.split(separator: ",").compactMap { Int64($0) }) }
    private var allCollapsed: Bool { !active.isEmpty && active.allSatisfy { collapsed.contains($0.id) } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Groups") {
                    ForEach(active) { groupRow($0) }
                }
                if !archived.isEmpty {
                    Section("Archived", isExpanded: Binding(get: { showArchived || !search.isEmpty }, set: { showArchived = $0 })) {
                        ForEach(archived) { groupRow($0) }
                    }
                }
            }
            .contextMenu(forSelectionType: SidebarItem.self) { items in
                contextMenu(for: items)
            } primaryAction: { items in
                // Double-click a group to show or hide its students.
                if items.count == 1, case .group(let id) = items.first, search.isEmpty {
                    setCollapsed([id], !collapsed.contains(id))
                }
            }
            .onDeleteCommand {
                if case .group(let id) = selection, let g = groups.first(where: { $0.id == id }) { deleting = g }
            }
            .safeAreaInset(edge: .bottom) { VersionFooter() }
            .searchable(text: $search, placement: .sidebar, prompt: "Search students")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                Button(allCollapsed ? "Show Students" : "Hide Students",
                       systemImage: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical") {
                    setCollapsed(active.map(\.id), !allCollapsed)
                }
                .help(allCollapsed ? "Show the students in every group" : "Collapse every group to just its name")
                Button("New Group…", systemImage: "folder.badge.plus") { startNaming(nil) }
                Button("Import Students…", systemImage: "square.and.arrow.down") { importing = true }
            }
        } detail: {
            detail
        }
        .sheet(isPresented: $importing) {
            ImportStudentsView(groups: groups.map(\.group), defaultGroupID: currentGroup?.id) { groupID in
                setCollapsed([groupID], false)
                selection = .group(groupID)
            }
        }
        .alert(naming?.title ?? "", isPresented: isPresent($naming), presenting: naming) { n in
            TextField("Group name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button(n.group == nil ? "Create" : "Rename") { commitName(n) }
                .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert(deleting.map { "Delete “\($0.group.name)”?" } ?? "", isPresented: isPresent($deleting), presenting: deleting) { g in
            Button("Delete", role: .destructive) { delete(g) }
            if !g.group.isArchived {
                Button("Archive Instead") { setArchived(g, true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { g in
            let sessions = g.students.reduce(0) { $0 + $1.sessionDates.count }
            Text("This permanently deletes \(g.students.count) students and \(sessions) sessions (transcripts and summaries). Recordings are moved to the Trash.\n\nTo only hide the group from the sidebar, archive it instead.")
        }
        .alert("Error", isPresented: isPresent($error)) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .task {
            do {
                for try await value in db.observeGroups() {
                    groups = value
                    if !isValid(selection) { selection = active.first.map { .group($0.id) } }
                }
            } catch {}
        }
    }

    // MARK: Sidebar rows

    /// The group with only the students matching the search, or nil if nothing matches.
    private func filtered(_ g: GroupProgress) -> GroupProgress? {
        guard !search.isEmpty else { return g }
        let q = StudentImporter.normalize(search)
        var g = g
        g.students = g.students.filter {
            StudentImporter.normalize($0.student.fullName).contains(q)
                || $0.student.mssv.contains(search)
                || StudentImporter.normalize($0.student.projectTitle).contains(q)
        }
        return g.students.isEmpty && !StudentImporter.normalize(g.group.name).contains(q) ? nil : g
    }

    /// The group's row, followed by its students unless collapsed; nothing if the search matches neither.
    /// Plain rows rather than a DisclosureGroup: the folder icon shows the state and double-click toggles it.
    @ViewBuilder private func groupRow(_ group: GroupProgress) -> some View {
        if let g = filtered(group) {
            let expanded = !search.isEmpty || !collapsed.contains(g.id)
            GroupRow(group: g, isExpanded: expanded).tag(SidebarItem.group(g.id))
            if expanded {
                ForEach(g.students) { p in
                    StudentRow(progress: p).tag(SidebarItem.student(p.id))
                        .padding(.leading, 22)
                }
            }
        }
    }

    @ViewBuilder private func contextMenu(for items: Set<SidebarItem>) -> some View {
        if items.isEmpty {
            Button("New Group…") { startNaming(nil) }
            Button("Import Students…") { importing = true }
        } else if items.count == 1, case .group(let id) = items.first, let g = groups.first(where: { $0.id == id }) {
            Button("Rename…") { startNaming(g.group) }
            Button("Import Students into Group…") {
                selection = .group(id)
                importing = true
            }
            Divider()
            if g.group.isArchived {
                Button("Unarchive") { setArchived(g, false) }
            } else {
                Button("Archive") { setArchived(g, true) }
            }
            Button("Delete…", role: .destructive) { deleting = g }
            Divider()
            Button("New Group…") { startNaming(nil) }
        }
    }

    private func setCollapsed(_ ids: [Int64], _ isCollapsed: Bool) {
        // Collapsing the group of the selected student selects the group, so the selection stays visible.
        if isCollapsed, case .student(let studentID) = selection,
           let owner = groups.first(where: { ids.contains($0.id) && $0.students.contains { $0.id == studentID } }) {
            selection = .group(owner.id)
        }
        var set = collapsed
        if isCollapsed { set.formUnion(ids) } else { set.subtract(ids) }
        collapsedRaw = set.sorted().map(String.init).joined(separator: ",")
    }

    private func isValid(_ item: SidebarItem?) -> Bool {
        switch item {
        case .group(let id): groups.contains { $0.id == id }
        case .student(let id): groups.contains { $0.students.contains { $0.id == id } }
        case nil: false
        }
    }

    // MARK: Group actions

    private func startNaming(_ group: StudentGroup?) {
        nameDraft = group?.name ?? ""
        naming = GroupNaming(group: group)
    }

    private func commitName(_ n: GroupNaming) {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            if let id = n.group?.id {
                try db.renameGroup(id: id, to: name)
            } else {
                let group = try db.createGroup(name: name)
                selection = group.id.map { .group($0) }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func setArchived(_ g: GroupProgress, _ archived: Bool) {
        do {
            try db.setGroupArchived(id: g.id, archived)
            if archived {
                setCollapsed([g.id], true)
            } else {
                setCollapsed([g.id], false)
                selection = .group(g.id)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ g: GroupProgress) {
        do {
            AppPaths.trashAudio(try db.deleteGroup(id: g.id))
            setCollapsed([g.id], false)
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .group(let id):
            let g = groups.first { $0.id == id }
            DashboardView(progress: g?.students ?? []) { selection = .student($0) }
                .navigationTitle(g?.group.name ?? "Dashboard")
                .navigationSubtitle(g?.group.isArchived == true ? "Archived" : "")
        case .student(let id):
            StudentDetailView(studentID: id, groupName: currentGroup?.group.name ?? "group").id(id)
        case nil:
            ContentUnavailableView {
                Label("No groups yet", systemImage: "folder")
            } description: {
                Text("Create a group, or import a student list (.xlsx) into a new one.")
            } actions: {
                Button("New Group…") { startNaming(nil) }
                Button("Import Students…") { importing = true }
            }
        }
    }
}

/// Create (group == nil) or rename a group.
private struct GroupNaming: Identifiable {
    let group: StudentGroup?
    var id: Int64 { group?.id ?? -1 }
    var title: String { group == nil ? "New Group" : "Rename Group" }
}

/// `isPresented` binding for an optional: true while set, clears it on dismiss.
private func isPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
}

private struct GroupRow: View {
    let group: GroupProgress
    let isExpanded: Bool
    var body: some View {
        let reported = group.students.filter { $0.hasReported(in: WeekCalendar.week(of: .now)) }.count
        Label {
            Text(group.group.name)
        } icon: {
            // Filled = open (students shown), outline = closed.
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .contentTransition(.symbolEffect(.replace))
        }
            .badge(group.students.isEmpty ? nil : Text("\(reported)/\(group.students.count)"))
            .help("\(reported) of \(group.students.count) students reported this week")
    }
}

/// App version at the bottom of the sidebar, replaced by a bubble when a newer release is out (D28).
/// Either one opens Sparkle's window: the update to install, or "You're up to date".
private struct VersionFooter: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Group {
            if let version = updater.status.availableVersion {
                Button { updater.checkForUpdates() } label: {
                    Label("New version \(version)", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.tint, in: .capsule)
                }
                .help("Follow \(version) is available (you have \(UpdateStatus.currentVersion())). Click to see what's new and install it.")
            } else {
                Button(UpdateStatus.currentVersion()) { updater.checkForUpdates() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Check for Updates…")
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct StudentRow: View {
    let progress: StudentProgress
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(progress.student.fullName)
                Text([progress.student.mssv, progress.student.projectTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            let reported = progress.hasReported(in: WeekCalendar.week(of: .now))
            Image(systemName: reported ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(reported ? .green : .secondary)
        }
    }
}
