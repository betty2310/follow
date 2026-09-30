import Foundation
import Testing
@testable import ProjectRecord

struct StudentImporterTests {
    @Test func guessesMappingFromVietnameseHeaders() {
        let mapping = StudentImporter.guessMapping(header: ["STT", "Họ và tên", "MSSV", "Lớp", "Tên đề tài", "Email"])
        #expect(mapping == [.fullName: 1, .mssv: 2, .className: 3, .projectTitle: 4, .email: 5])
    }

    @Test func headerMatchingIgnoresCaseAndAccents() {
        let mapping = StudentImporter.guessMapping(header: ["mssv", "HO TEN"])
        #expect(mapping == [.mssv: 0, .fullName: 1])
    }

    @Test func unknownHeadersLeaveFieldsUnmapped() {
        let mapping = StudentImporter.guessMapping(header: ["Code", "Student", "Group"])
        #expect(StudentImporter.missingRequired(mapping) == [.mssv, .fullName])
    }

    @Test func mapsRowsWithManualMappingAndSkipsIncompleteRows() throws {
        let table = [
            ["Code", "Student", "Topic"],
            ["2110001", "Nguyễn Văn A", "Chat app"],
            ["", "Missing ID", ""],
        ]
        let rows = try StudentImporter.rows(from: table, mapping: [.mssv: 0, .fullName: 1, .projectTitle: 2])
        #expect(rows == [.init(mssv: "2110001", fullName: "Nguyễn Văn A", className: "", projectTitle: "Chat app", email: "")])
    }

    @Test func noHeaderRowKeepsFirstRow() throws {
        let rows = try StudentImporter.rows(from: [["1", "A"], ["2", "B"]], mapping: [.mssv: 0, .fullName: 1], firstRowIsHeader: false)
        #expect(rows.map(\.mssv) == ["1", "2"])
    }

    @Test func missingRequiredMappingThrows() {
        #expect(throws: StudentImporter.Failure.self) { try StudentImporter.rows(from: [["x"]], mapping: [.mssv: 0]) }
    }

    /// Same headers as the real HUST list: "Mã số SV/HV | Họ tên SV/HV | Email" (fake data).
    @Test func importsRealWorldHeaderFormatFromXLSX() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/students-sample.xlsx")
        let table = try StudentImporter.readTable(url: url)
        let mapping = StudentImporter.guessMapping(header: table[0])
        #expect(mapping == [.mssv: 0, .fullName: 1, .email: 2])
        let rows = try StudentImporter.rows(from: table, mapping: mapping)
        #expect(rows.map(\.mssv) == ["20230001", "202400002"])
        #expect(rows[1].fullName == "Trần Thị Mẫu")
    }

    @Test func columnLettersRoundTrip() {
        for i in [0, 25, 26, 51, 701, 702] {
            #expect(StudentImporter.columnIndex(StudentImporter.columnLetter(i)) == i)
        }
        #expect(StudentImporter.columnLetter(26) == "AA")
    }
}

struct NameNormalizationTests {
    @Test func capitalizesFirstLetterOfEachWord() {
        #expect(StudentImporter.normalizeName("NGUYỄN HÀ ANH") == "Nguyễn Hà Anh")
        #expect(StudentImporter.normalizeName("  trần   chí cường ") == "Trần Chí Cường")
        #expect(StudentImporter.normalizeName("đỗ đức") == "Đỗ Đức")
    }

    @Test func convertsDecomposedUnicodeToNFC() {
        let decomposed = "Nguye\u{0302}\u{0303}n"   // "Nguyễn" as base letter + combining marks
        let result = StudentImporter.normalizeName(decomposed)
        #expect(result == "Nguyễn")
        #expect(result.unicodeScalars.count == "Nguyễn".unicodeScalars.count)
    }

    @Test func importNormalizesNameAndEmail() throws {
        let rows = try StudentImporter.rows(from: [["MSSV", "Họ tên", "Email"], [" 123 ", "LÊ  VĂN B", " B@Example.COM "]],
                                            mapping: [.mssv: 0, .fullName: 1, .email: 2])
        #expect(rows == [.init(mssv: "123", fullName: "Lê Văn B", className: "", projectTitle: "", email: "b@example.com")])
    }
}

struct AppDatabaseTests {
    private func row(_ mssv: String, _ name: String, project: String = "") -> StudentImporter.Row {
        .init(mssv: mssv, fullName: name, className: "", projectTitle: project, email: "")
    }

    @Test func importIntoNewGroupThenMergeNeverDeletes() throws {
        let db = try AppDatabase.inMemory()
        let groupID = try db.importStudents([row("1", "An"), row("2", "Bình")], intoNewGroupNamed: "Đồ án 1")

        let rows = [row("2", "Bình", project: "Chat app"), row("3", "Cường"), row("1", "An")]
        #expect(try db.planImport(rows, into: groupID) == .init(new: 1, updated: 1, unchanged: 1))
        try db.importStudents(rows, into: groupID)

        let students = try db.progress(groupId: groupID).map(\.student)
        #expect(students.map(\.mssv) == ["1", "2", "3"])
        #expect(students[1].projectTitle == "Chat app")

        // A re-import without student 3 keeps them.
        try db.importStudents([row("1", "An")], into: groupID)
        #expect(try db.progress(groupId: groupID).count == 3)
    }

    @Test func sameMSSVInTwoGroupsIsTwoStudents() throws {
        let db = try AppDatabase.inMemory()
        let g1 = try db.importStudents([row("1", "An")], intoNewGroupNamed: "A")
        let g2 = try db.importStudents([row("1", "An")], intoNewGroupNamed: "B")
        #expect(try db.progress(groupId: g1).first?.id != db.progress(groupId: g2).first?.id)
    }

    @Test func sessionsRoundTripAndDriveProgress() throws {
        let db = try AppDatabase.inMemory()
        let g = try db.importStudents([row("1", "An")], intoNewGroupNamed: "A")
        let studentID = try db.progress(groupId: g)[0].id
        let s = try db.insertSession(Session(studentId: studentID, date: .now, audioPath: "audio/x.m4a"))
        try db.updateSession(id: s.id!) {
            $0.utterances = [Utterance(speaker: "A", text: "Xin chào", start: 0, end: 1)]
            $0.status = .done
        }
        let loaded = try #require(try db.session(id: s.id!))
        #expect(loaded.utterances.first?.text == "Xin chào")
        #expect(loaded.status == .done)
        #expect(try db.progress(groupId: g)[0].hasReported(in: WeekCalendar.week(of: .now)))
    }
}

struct ClaudeCLISummarizerTests {
    @Test func parsesEnvelopeWithFencedJSON() throws {
        let inner = "```json\n{\"teacher_speaker\": \"B\", \"summary_markdown\": \"## Đã làm được\\n- X\"}\n```"
        let envelope = try JSONSerialization.data(withJSONObject: ["type": "result", "result": inner])
        let result = try ClaudeCLISummarizer.parse(cliOutput: envelope)
        #expect(result.teacherSpeaker == "B")
        #expect(result.summaryMarkdown.hasPrefix("## Đã làm được"))
    }
}

struct WeekCalendarTests {
    @Test func weeksStartOnMonday() {
        let c = WeekCalendar.calendar
        let sunday = c.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
        let monday = c.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        #expect(WeekCalendar.week(of: sunday) != WeekCalendar.week(of: monday))
    }
}
