import SwiftUI

/// Sidebar-driven layout (docs/DECISIONS.md D17): search on top, Dashboard + Settings, then the students of the selected group.
enum SidebarItem: Hashable {
    case dashboard
    case settings
    case student(Int64)
}

struct ContentView: View {
    @Environment(\.appDatabase) private var db
    @State private var groups: [StudentGroup] = []
    @State private var progress: [StudentProgress] = []
    @State private var selectedGroupID: Int64?
    @State private var selection: SidebarItem? = .dashboard
    @State private var search = ""
    @State private var importing = false

    private var group: StudentGroup? { groups.first { $0.id == selectedGroupID } ?? groups.first }

    private var filtered: [StudentProgress] {
        guard !search.isEmpty else { return progress }
        let q = StudentImporter.normalize(search)
        return progress.filter {
            StudentImporter.normalize($0.student.fullName).contains(q)
                || $0.student.mssv.contains(search)
                || StudentImporter.normalize($0.student.projectTitle).contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Dashboard", systemImage: "square.grid.2x2").tag(SidebarItem.dashboard)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)

                Section {
                    ForEach(filtered) { p in
                        StudentRow(progress: p).tag(SidebarItem.student(p.id))
                    }
                } header: {
                    groupHeader
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search students")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                Button("Import Students…", systemImage: "square.and.arrow.down") { importing = true }
            }
        } detail: {
            detail
        }
        .sheet(isPresented: $importing) {
            ImportStudentsView(groups: groups, defaultGroupID: group?.id) { groupID in
                selectedGroupID = groupID
                selection = .dashboard
            }
        }
        .task {
            do { for try await value in db.observeGroups() { groups = value } } catch {}
        }
        .task(id: group?.id) {
            guard let id = group?.id else { progress = []; return }
            do { for try await value in db.observeProgress(groupId: id) { progress = value } } catch {}
        }
    }

    @ViewBuilder private var groupHeader: some View {
        if groups.count > 1 {
            Picker("Group", selection: Binding(get: { group?.id }, set: { selectedGroupID = $0 })) {
                ForEach(groups) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        } else {
            Text(group?.name ?? "Students")
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .dashboard, nil:
            DashboardView(progress: progress) { selection = .student($0) }
                .navigationTitle(group?.name ?? "Dashboard")
        case .settings:
            SettingsView()
        case .student(let id):
            StudentDetailView(studentID: id, groupName: group?.name ?? "group").id(id)
        }
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
