import SwiftData
import SwiftUI

/// Sidebar-driven layout: search on top, Dashboard + Settings, then the students of the selected term.
enum SidebarItem: Hashable {
    case dashboard
    case settings
    case student(PersistentIdentifier)
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Term.createdAt, order: .reverse) private var terms: [Term]
    @State private var selectedTermID: PersistentIdentifier?
    @State private var selection: SidebarItem? = .dashboard
    @State private var search = ""
    @State private var importing = false

    private var term: Term? { terms.first { $0.persistentModelID == selectedTermID } ?? terms.first }

    private var students: [Student] {
        let all = (term?.students ?? []).sorted { $0.fullName < $1.fullName }
        guard !search.isEmpty else { return all }
        let q = StudentImporter.normalize(search)
        return all.filter {
            StudentImporter.normalize($0.fullName).contains(q)
                || $0.mssv.contains(search)
                || StudentImporter.normalize($0.projectTitle).contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Dashboard", systemImage: "square.grid.2x2").tag(SidebarItem.dashboard)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)

                Section {
                    ForEach(students) { student in
                        StudentRow(student: student).tag(SidebarItem.student(student.persistentModelID))
                    }
                } header: {
                    termHeader
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
            ImportStudentsView { term in
                selectedTermID = term.persistentModelID
                selection = .dashboard
            }
        }
    }

    @ViewBuilder private var termHeader: some View {
        if terms.count > 1 {
            Picker("Term", selection: Binding(get: { term?.persistentModelID }, set: { selectedTermID = $0 })) {
                ForEach(terms) { Text($0.name).tag(Optional($0.persistentModelID)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        } else {
            Text(term?.name ?? "Students")
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .dashboard, nil:
            DashboardView(students: term?.students ?? []) { selection = .student($0.persistentModelID) }
        case .settings:
            SettingsView()
        case .student(let id):
            if let student = term?.students.first(where: { $0.persistentModelID == id }) {
                StudentDetailView(student: student).id(id)
            } else {
                ContentUnavailableView("Select a student", systemImage: "person.crop.circle")
            }
        }
    }
}

private struct StudentRow: View {
    let student: Student
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(student.fullName)
                Text("\(student.mssv) · \(student.projectTitle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            let reported = student.hasReported(in: WeekCalendar.week(of: .now))
            Image(systemName: reported ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(reported ? .green : .secondary)
        }
    }
}

extension Student {
    func hasReported(in week: WeekID) -> Bool {
        sessions.contains { WeekCalendar.week(of: $0.date) == week }
    }
}
