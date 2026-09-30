import CoreXLSX
import Foundation

/// Parses the per-term student list (.xlsx). Expected headers (docs/DECISIONS.md D10):
/// `MSSV | Họ tên | Lớp | Tên đề tài | Email`. MSSV and Họ tên are required; header matching is
/// case-, accent- and whitespace-insensitive, so small variations still work.
enum StudentImporter {
    struct Row: Equatable, Sendable {
        var mssv, fullName, className, projectTitle, email: String
    }

    enum Failure: LocalizedError {
        case unreadable
        case missingColumns([String])
        var errorDescription: String? {
            switch self {
            case .unreadable: "Could not read the Excel file."
            case .missingColumns(let cols): "Missing required column(s): \(cols.joined(separator: ", "))"
            }
        }
    }

    static func parse(url: URL) throws -> [Row] {
        guard let file = XLSXFile(filepath: url.path),
              let path = try file.parseWorksheetPaths().first
        else { throw Failure.unreadable }
        let sheet = try file.parseWorksheet(at: path)
        let strings = try file.parseSharedStrings()
        let table: [[String]] = (sheet.data?.rows ?? []).map { row in
            var values: [String] = []
            for cell in row.cells {
                let col = columnIndex(cell.reference.column.value)
                while values.count < col { values.append("") }
                let v = strings.flatMap { cell.stringValue($0) } ?? cell.inlineString?.text ?? cell.value ?? ""
                values.append(v.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return values
        }
        return try rows(from: table)
    }

    /// Maps a raw table (first row = header) to student rows. Separated from `parse` for testing.
    static func rows(from table: [[String]]) throws -> [Row] {
        guard let header = table.first else { return [] }
        let keys = header.map(normalize)
        func idx(_ names: String...) -> Int? { keys.firstIndex { names.map(normalize).contains($0) } }

        let iMSSV = idx("MSSV", "Mã số sinh viên", "Student ID")
        let iName = idx("Họ tên", "Họ và tên", "Full name", "Name")
        var missing: [String] = []
        if iMSSV == nil { missing.append("MSSV") }
        if iName == nil { missing.append("Họ tên") }
        guard let iMSSV, let iName else { throw Failure.missingColumns(missing) }
        let iClass = idx("Lớp", "Class"), iTitle = idx("Tên đề tài", "Đề tài", "Project"), iEmail = idx("Email")

        return table.dropFirst().compactMap { r in
            func at(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            let mssv = at(iMSSV), name = at(iName)
            guard !mssv.isEmpty, !name.isEmpty else { return nil }
            return Row(mssv: mssv, fullName: name, className: at(iClass), projectTitle: at(iTitle), email: at(iEmail))
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d")
            .filter { !$0.isWhitespace }
    }

    /// "A" → 0, "Z" → 25, "AA" → 26
    private static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }
}
