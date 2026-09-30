import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Term.createdAt, order: .reverse) private var terms: [Term]
    @State private var selectedTermID: PersistentIdentifier?
    @State private var selectedStudent: Student?
    @State private var importing = false
    @State private var importError: String?

    private var term: Term? { terms.first { $0.persistentModelID == selectedTermID } ?? terms.first }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedStudent) {
                ForEach((term?.students ?? []).sorted { $0.fullName < $1.fullName }) { student in
                    StudentRow(student: student).tag(student)
                }
            }
            .navigationTitle(term?.name ?? "No term")
            .toolbar {
                if terms.count > 1 {
                    Picker("Term", selection: $selectedTermID) {
                        ForEach(terms) { Text($0.name).tag(Optional($0.persistentModelID)) }
                    }
                }
                Button("Import Students…", systemImage: "square.and.arrow.down") { importing = true }
            }
        } detail: {
            if let selectedStudent {
                StudentDetailView(student: selectedStudent)
            } else {
                ContentUnavailableView("Select a student", systemImage: "person.crop.circle")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "xlsx")!]) { result in
            importStudents(result)
        }
        .alert("Import failed", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private func importStudents(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let rows = try StudentImporter.parse(url: url)
            let term = Term(name: url.deletingPathExtension().lastPathComponent)
            context.insert(term)
            for r in rows {
                let s = Student(mssv: r.mssv, fullName: r.fullName, className: r.className, projectTitle: r.projectTitle, email: r.email)
                s.term = term
                context.insert(s)
            }
            selectedTermID = term.persistentModelID
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct StudentRow: View {
    let student: Student
    var reportedThisWeek: Bool {
        let now = WeekCalendar.week(of: .now)
        return student.sessions.contains { WeekCalendar.week(of: $0.date) == now }
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(student.fullName)
                Text("\(student.mssv) · \(student.projectTitle)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: reportedThisWeek ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(reportedThisWeek ? .green : .secondary)
        }
    }
}
