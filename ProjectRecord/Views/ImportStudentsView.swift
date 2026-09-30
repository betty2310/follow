import SwiftUI
import UniformTypeIdentifiers

/// Import sheet (docs/DECISIONS.md D18): explains the expected columns, lets the teacher pick a file,
/// map each field to a column (auto-guessed), choose the target group (existing or new), preview, then import.
/// Importing into an existing group adds new MSSVs and updates existing ones; it never deletes (D20).
struct ImportStudentsView: View {
    enum Target: Hashable { case new, existing(Int64) }

    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let groups: [StudentGroup]
    let defaultGroupID: Int64?
    var onImported: (Int64) -> Void

    @State private var target: Target = .new

    @State private var fileURL: URL?
    @State private var table: [[String]] = []
    @State private var mapping: StudentImporter.Mapping = [:]
    @State private var firstRowIsHeader = true
    @State private var newGroupName = ""
    @State private var picking = false
    @State private var error: String?

    private var columnCount: Int { table.map(\.count).max() ?? 0 }
    private var header: [String] { table.first ?? [] }
    private var missing: [StudentImporter.Field] { StudentImporter.missingRequired(mapping) }
    private var preview: [StudentImporter.Row] {
        (try? StudentImporter.rows(from: table, mapping: mapping, firstRowIsHeader: firstRowIsHeader)) ?? []
    }
    private var targetGroupID: Int64? {
        if case .existing(let id) = target { id } else { nil }
    }
    private var plan: AppDatabase.ImportPlan? { try? db.planImport(preview, into: targetGroupID) }
    private var targetIsValid: Bool {
        target != .new || !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                instructions
                if fileURL != nil {
                    groupSection
                    mappingSection
                    previewSection
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                else if fileURL != nil && !missing.isEmpty {
                    Text("Map required: \(missing.map(\.title).joined(separator: ", "))").foregroundStyle(.orange).font(.caption)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import", action: importNow)
                    .keyboardShortcut(.defaultAction)
                    .disabled(fileURL == nil || !missing.isEmpty || preview.isEmpty || !targetIsValid)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 560)
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "xlsx")!]) { load($0) }
        .onAppear { if let defaultGroupID { target = .existing(defaultGroupID) } }
    }

    private var instructions: some View {
        Section("Student list (.xlsx)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("One row per student, first sheet only. Column names don't have to match exactly; you'll map them in the next step.")
                ForEach(StudentImporter.Field.allCases) { f in
                    Label(f.title + (f.isRequired ? "  (required)" : "  (optional)"),
                          systemImage: f.isRequired ? "asterisk.circle.fill" : "circle")
                        .foregroundStyle(f.isRequired ? .primary : .secondary)
                }
                Text("Example header:  MSSV | Họ tên | Lớp | Tên đề tài | Email")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            HStack {
                Text(fileURL?.lastPathComponent ?? "No file chosen").foregroundStyle(.secondary)
                Spacer()
                Button(fileURL == nil ? "Choose File…" : "Change File…") { picking = true }
            }
        }
    }

    private var groupSection: some View {
        Section("Import into group") {
            Picker("Group", selection: $target) {
                ForEach(groups) { g in Text(g.name).tag(Target.existing(g.id!)) }
                if !groups.isEmpty { Divider() }
                Text("New group…").tag(Target.new)
            }
            if target == .new {
                TextField("New group name", text: $newGroupName, prompt: Text("e.g. Đồ án 1 – 2025.1"))
            }
        }
    }

    private var mappingSection: some View {
        Section("Column mapping") {
            Toggle("First row is a header", isOn: $firstRowIsHeader)
            ForEach(StudentImporter.Field.allCases) { field in
                Picker(selection: binding(for: field)) {
                    Text(field.isRequired ? "— choose column —" : "— none —").tag(Int?.none)
                    ForEach(0..<columnCount, id: \.self) { i in
                        Text(columnLabel(i)).tag(Int?.some(i))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(field.title)
                        if field.isRequired {
                            Image(systemName: mapping[field] == nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(mapping[field] == nil ? .orange : .green)
                        }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Section(previewTitle) {
            if preview.isEmpty {
                Text("No valid rows yet. Check the mapping.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(preview.prefix(5).enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(r.mssv).monospaced().frame(width: 100, alignment: .leading)
                        Text(r.fullName)
                        Spacer()
                        Text([r.className, r.projectTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if preview.count > 5 { Text("… and \(preview.count - 5) more").foregroundStyle(.secondary) }
            }
        }
    }

    private var previewTitle: String {
        guard let plan else { return "Preview" }
        var parts = ["\(plan.new) new"]
        if plan.updated > 0 { parts.append("\(plan.updated) updated") }
        if plan.unchanged > 0 { parts.append("\(plan.unchanged) unchanged") }
        return "Preview: " + parts.joined(separator: " · ")
    }

    private func columnLabel(_ i: Int) -> String {
        let letter = StudentImporter.columnLetter(i)
        let sample = firstRowIsHeader ? (i < header.count ? header[i] : "") : (table.first.flatMap { i < $0.count ? $0[i] : nil } ?? "")
        return sample.isEmpty ? "Column \(letter)" : "Column \(letter): \(sample)"
    }

    private func binding(for field: StudentImporter.Field) -> Binding<Int?> {
        Binding(
            get: { mapping[field] },
            set: { newValue in
                // Keep each column assigned to at most one field.
                if let newValue, let other = mapping.first(where: { $0.value == newValue && $0.key != field })?.key {
                    mapping[other] = nil
                }
                mapping[field] = newValue
            }
        )
    }

    private func load(_ result: Result<URL, Error>) {
        error = nil
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            table = try StudentImporter.readTable(url: url)
            mapping = StudentImporter.guessMapping(header: table.first ?? [])
            fileURL = url
            if newGroupName.isEmpty { newGroupName = url.deletingPathExtension().lastPathComponent }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importNow() {
        do {
            let groupID: Int64
            if let targetGroupID {
                groupID = targetGroupID
                try db.importStudents(preview, into: groupID)
            } else {
                groupID = try db.importStudents(preview, intoNewGroupNamed: newGroupName)
            }
            onImported(groupID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
