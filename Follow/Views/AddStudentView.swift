import SwiftUI

/// Add one student by hand (docs/DECISIONS.md D34): name and MSSV required, email and project title optional.
/// The values are cleaned like an import (D21). An MSSV already in the group is refused, not updated.
struct AddStudentView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let groups: [StudentGroup]
    let defaultGroupID: Int64?
    var onAdded: (Student) -> Void

    @State private var groupID: Int64?
    @State private var fullName = ""
    @State private var mssv = ""
    @State private var email = ""
    @State private var projectTitle = ""
    @State private var error: String?

    private var row: StudentImporter.Row? {
        StudentImporter.row(mssv: mssv, fullName: fullName, projectTitle: projectTitle, email: email)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Group", selection: $groupID) {
                    ForEach(groups) { g in Text(g.name).tag(g.id) }
                }
                Section {
                    TextField("Full name", text: $fullName, prompt: Text("Required"))
                    TextField("Student ID (MSSV)", text: $mssv, prompt: Text("Required"))
                }
                Section {
                    TextField("Email", text: $email, prompt: Text("Optional"))
                    TextField("Project title", text: $projectTitle, prompt: Text("Optional"))
                }
            }
            .formStyle(.grouped)
            .onChange(of: mssv) { error = nil }
            .onChange(of: groupID) { error = nil }

            Divider()
            HStack {
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(row == nil || groupID == nil)
            }
            .padding()
        }
        .frame(minWidth: 440)
        .onAppear { groupID = defaultGroupID ?? groups.first?.id }
    }

    private func add() {
        guard let row, let groupID else { return }
        do {
            let student = try db.addStudent(row, to: groupID)
            onAdded(student)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
