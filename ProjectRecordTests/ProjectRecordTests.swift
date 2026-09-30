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
        #expect(rows[1].fullName == "TRẦN THỊ MẪU")
    }

    @Test func columnLettersRoundTrip() {
        for i in [0, 25, 26, 51, 701, 702] {
            #expect(StudentImporter.columnIndex(StudentImporter.columnLetter(i)) == i)
        }
        #expect(StudentImporter.columnLetter(26) == "AA")
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
