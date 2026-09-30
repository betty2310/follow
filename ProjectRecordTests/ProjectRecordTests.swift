import Foundation
import Testing
@testable import ProjectRecord

struct StudentImporterTests {
    @Test func mapsVietnameseHeaders() throws {
        let table = [
            ["MSSV", "Họ và tên", "Lớp", "Tên đề tài", "Email"],
            ["2110001", "Nguyễn Văn A", "CS01", "Chat app", "a@example.com"],
            ["", "Missing ID", "", "", ""],
        ]
        let rows = try StudentImporter.rows(from: table)
        #expect(rows == [.init(mssv: "2110001", fullName: "Nguyễn Văn A", className: "CS01", projectTitle: "Chat app", email: "a@example.com")])
    }

    @Test func headerMatchingIgnoresCaseAndAccents() throws {
        let rows = try StudentImporter.rows(from: [["mssv", "HO TEN"], ["1", "B"]])
        #expect(rows.first?.fullName == "B")
    }

    @Test func missingRequiredColumnThrows() {
        #expect(throws: StudentImporter.Failure.self) { try StudentImporter.rows(from: [["Email"]]) }
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
