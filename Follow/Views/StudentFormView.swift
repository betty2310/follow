import SwiftUI

/// Add one student by hand (docs/DECISIONS.md D34), or edit one (`student` set, D37): name and MSSV required,
/// email and project title optional. The values are cleaned like an import (D21).
/// An MSSV already used by another student of the group is refused, not merged.
struct StudentFormView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let groups: [StudentGroup]
    let defaultGroupID: Int64?
    /// The student to edit; nil adds a new one.
    var student: Student? = nil
    var onSaved: (Student) -> Void

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
                    field("Full name", text: $fullName, prompt: "Required")
                    field("Student ID (MSSV)", text: $mssv, prompt: "Required")
                }
                Section {
                    field("Email", text: $email, prompt: "Optional")
                    field("Project title", text: $projectTitle, prompt: "Optional")
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
                Button(student == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(row == nil || groupID == nil)
            }
            .padding()
        }
        .frame(minWidth: 440)
        .onAppear {
            if let student {
                groupID = student.groupId
                fullName = student.fullName
                mssv = student.mssv
                email = student.email
                projectTitle = student.projectTitle
            } else {
                groupID = defaultGroupID ?? groups.first?.id
            }
        }
    }

    /// A grouped form right-aligns its fields, which fights Vietnamese input methods: type from the left.
    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        TextField(label, text: text, prompt: Text(prompt))
            .multilineTextAlignment(.leading)
    }

    private func save() {
        guard let row, let groupID else { return }
        do {
            let saved = if let id = student?.id {
                try db.updateStudent(id: id, row, groupId: groupID)
            } else {
                try db.addStudent(row, to: groupID)
            }
            onSaved(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
