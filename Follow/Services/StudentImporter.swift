import CoreXLSX
import Foundation

/// Reads the per-term student list (.xlsx) and maps its columns to student fields (docs/DECISIONS.md D10, D18).
/// Flow: `readTable` → `guessMapping` (auto-match headers) → user adjusts in `ImportStudentsView` → `rows(from:mapping:)`.
enum StudentImporter {
    /// Student fields a column can be mapped to. `mssv` and `fullName` are required.
    enum Field: String, CaseIterable, Identifiable, Sendable {
        case mssv, fullName, className, projectTitle, email
        var id: Self { self }

        var title: String {
            switch self {
            case .mssv: "Student ID (MSSV)"
            case .fullName: "Full name (Họ tên)"
            case .className: "Class (Lớp)"
            case .projectTitle: "Project title (Tên đề tài)"
            case .email: "Email"
            }
        }

        var isRequired: Bool { self == .mssv || self == .fullName }

        /// Header names auto-matched to this field (compared after `normalize`).
        var aliases: [String] {
            switch self {
            case .mssv: ["MSSV", "MSHV", "Mã số sinh viên", "Mã số SV", "Mã SV", "Mã số", "Student ID", "ID"]
            case .fullName: ["Họ tên", "Họ và tên", "Tên sinh viên", "Full name", "Name"]
            case .className: ["Lớp", "Class"]
            case .projectTitle: ["Tên đề tài", "Đề tài", "Dự án", "Project", "Project title"]
            case .email: ["Email", "E-mail"]
            }
        }
    }

    /// Field → column index in the table.
    typealias Mapping = [Field: Int]

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

    /// Reads the first worksheet into a rectangular-ish table of trimmed strings.
    static func readTable(url: URL) throws -> [[String]] {
        guard let file = XLSXFile(filepath: url.path),
              let path = try file.parseWorksheetPaths().first
        else { throw Failure.unreadable }
        let sheet = try file.parseWorksheet(at: path)
        let strings = try file.parseSharedStrings()
        return (sheet.data?.rows ?? []).map { row in
            var values: [String] = []
            for cell in row.cells {
                let col = columnIndex(cell.reference.column.value)
                while values.count < col { values.append("") }
                let v = strings.flatMap { cell.stringValue($0) } ?? cell.inlineString?.text ?? cell.value ?? ""
                values.append(v.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return values
        }
        .filter { $0.contains { !$0.isEmpty } }
    }

    /// Auto-matches header cells to fields. Each column is used at most once.
    /// Pass 1: exact match on an alias. Pass 2: header *contains* an alias (≥ 4 chars), so real headers
    /// like "Mã số SV/HV" or "Họ tên SV/HV" still match.
    static func guessMapping(header: [String]) -> Mapping {
        let keys = header.map(normalize)
        var mapping: Mapping = [:]
        let matchers: [(String, String) -> Bool] = [
            { key, alias in key == alias },
            { key, alias in alias.count >= 4 && key.contains(alias) },
        ]
        for matches in matchers {
            for field in Field.allCases where mapping[field] == nil {
                let aliases = field.aliases.map(normalize)
                if let i = keys.indices.first(where: { i in
                    !mapping.values.contains(i) && aliases.contains { matches(keys[i], $0) }
                }) {
                    mapping[field] = i
                }
            }
        }
        return mapping
    }

    static func missingRequired(_ mapping: Mapping) -> [Field] {
        Field.allCases.filter { $0.isRequired && mapping[$0] == nil }
    }

    /// Maps table rows to students. Rows without MSSV or name are skipped.
    static func rows(from table: [[String]], mapping: Mapping, firstRowIsHeader: Bool = true) throws -> [Row] {
        let missing = missingRequired(mapping)
        guard missing.isEmpty else { throw Failure.missingColumns(missing.map(\.title)) }
        return table.dropFirst(firstRowIsHeader ? 1 : 0).compactMap { r in
            func at(_ f: Field) -> String { mapping[f].flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            let mssv = cleanText(at(.mssv)), name = normalizeName(at(.fullName))
            guard !mssv.isEmpty, !name.isEmpty else { return nil }
            return Row(mssv: mssv, fullName: name, className: cleanText(at(.className)),
                       projectTitle: cleanText(at(.projectTitle)), email: cleanText(at(.email)).lowercased())
        }
    }

    /// Unicode NFC + trimmed + collapsed whitespace. NFC matters: Vietnamese copied from Excel/web may be
    /// decomposed (e.g. "e" + combining marks), which breaks search and MSSV/name matching.
    static func cleanText(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// "NGUYỄN  hà ANH" → "Nguyễn Hà Anh" (docs/DECISIONS.md D21). Applied on import only.
    static func normalizeName(_ s: String) -> String {
        let vi = Locale(identifier: "vi")
        return cleanText(s)
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased(with: vi) + word.dropFirst().lowercased(with: vi) }
            .joined(separator: " ")
    }

    /// Key for fuzzy matching (headers, search): no case, no accents, no whitespace.
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d")
            .filter { !$0.isWhitespace }
    }

    /// "A" → 0, "Z" → 25, "AA" → 26
    static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// 0 → "A", 26 → "AA"
    static func columnLetter(_ index: Int) -> String {
        var n = index + 1, s = ""
        while n > 0 { n -= 1; s = String(UnicodeScalar(65 + n % 26)!) + s; n /= 26 }
        return s
    }
}
