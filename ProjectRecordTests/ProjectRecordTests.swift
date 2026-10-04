import Foundation
import GRDB
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

    @Test func renameAndArchiveGroupKeepStudents() throws {
        let db = try AppDatabase.inMemory()
        let g = try db.importStudents([row("1", "An")], intoNewGroupNamed: "A")
        try db.renameGroup(id: g, to: "  Đồ án 2  ")
        try db.setGroupArchived(id: g, true)

        var group = try #require(try db.groups().first)
        #expect(group.group.name == "Đồ án 2")
        #expect(group.group.isArchived)
        #expect(group.students.count == 1)

        try db.setGroupArchived(id: g, false)
        group = try #require(try db.groups().first)
        #expect(!group.group.isArchived)
    }

    @Test func deleteGroupCascadesAndReturnsAudioPaths() throws {
        let db = try AppDatabase.inMemory()
        let keep = try db.importStudents([row("1", "An")], intoNewGroupNamed: "Keep")
        let drop = try db.importStudents([row("1", "An"), row("2", "Bình")], intoNewGroupNamed: "Drop")
        for (i, p) in try db.progress(groupId: drop).enumerated() {
            _ = try db.insertSession(Session(studentId: p.id, date: .now, audioPath: "audio/Drop/\(i).m4a"))
        }
        _ = try db.insertSession(Session(studentId: db.progress(groupId: keep)[0].id, date: .now, audioPath: "audio/Keep/0.m4a"))

        #expect(try db.deleteGroup(id: drop).sorted() == ["audio/Drop/0.m4a", "audio/Drop/1.m4a"])
        #expect(try db.groups().map(\.id) == [keep])
        #expect(try db.writer.read { try Session.fetchCount($0) } == 1)
        #expect(try db.writer.read { try Student.fetchCount($0) } == 1)
    }

    @Test func groupsSnapshotHasEachGroupsStudents() throws {
        let db = try AppDatabase.inMemory()
        let a = try db.importStudents([row("1", "An")], intoNewGroupNamed: "A")
        let b = try db.importStudents([row("2", "Bình"), row("3", "Cường")], intoNewGroupNamed: "B")
        let groups = try db.groups()
        #expect(groups.first { $0.id == a }?.students.map(\.student.mssv) == ["1"])
        #expect(groups.first { $0.id == b }?.students.map(\.student.mssv) == ["2", "3"])
    }

    @Test func sessionNoteRoundTrips() throws {
        let db = try AppDatabase.inMemory()
        let g = try db.importStudents([row("1", "An")], intoNewGroupNamed: "A")
        let s = try db.insertSession(Session(studentId: db.progress(groupId: g)[0].id, date: .now, audioPath: "a.m4a"))
        #expect(s.note == "")
        try db.updateSession(id: s.id!) { $0.note = "Chưa có demo, hẹn tuần sau." }
        #expect(try db.session(id: s.id!)?.note == "Chưa có demo, hẹn tuần sau.")
    }

    @Test func setProjectTitleTrimsAndKeepsOtherFields() throws {
        let db = try AppDatabase.inMemory()
        let g = try db.importStudents([row("1", "An", project: "Web bán hàng")], intoNewGroupNamed: "A")
        let id = try db.progress(groupId: g)[0].id
        try db.setProjectTitle(studentId: id, "  App đặt lịch  ")
        let student = try #require(try db.student(id: id))
        #expect(student.projectTitle == "App đặt lịch")
        #expect(student.fullName == "An")
    }

    @Test func deleteSessionReturnsAudioPathAndKeepsOthers() throws {
        let db = try AppDatabase.inMemory()
        let g = try db.importStudents([row("1", "An")], intoNewGroupNamed: "A")
        let studentID = try db.progress(groupId: g)[0].id
        let drop = try db.insertSession(Session(studentId: studentID, date: .now, audioPath: "audio/A/1/drop.m4a"))
        let keep = try db.insertSession(Session(studentId: studentID, date: .now, audioPath: "audio/A/1/keep.m4a"))

        #expect(try db.deleteSession(id: drop.id!) == "audio/A/1/drop.m4a")
        #expect(try db.deleteSession(id: drop.id!) == nil)
        #expect(try db.session(id: keep.id!) != nil)
        #expect(try db.progress(groupId: g)[0].sessionDates.count == 1)
    }

    @Test func migrationGivesExistingSessionsAnEmptyNote() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3-group-archive")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO studentGroup (id, name, createdAt) VALUES (1, 'A', ?)",
                           arguments: [DBTimestamp.string(.now)])
            try db.execute(sql: "INSERT INTO student (id, groupId, mssv, fullName, projectTitle) VALUES (1, 1, '1', 'An', 'Web bán hàng')")
            try db.execute(sql: "INSERT INTO session (id, studentId, date, audioPath, status) VALUES (1, 1, ?, 'a.m4a', 'done')",
                           arguments: [DBTimestamp.string(.now)])
        }
        let db = try AppDatabase(queue)
        #expect(try db.session(id: 1)?.note == "")
    }

    @Test func migrationDropsSessionProjectTitleFromEarlyDevBuild() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3-group-archive")
        try queue.write { db in
            try db.execute(sql: """
                ALTER TABLE session ADD COLUMN projectTitle TEXT NOT NULL DEFAULT '';
                ALTER TABLE session ADD COLUMN note TEXT NOT NULL DEFAULT '';
                INSERT INTO grdb_migrations (identifier) VALUES ('v4-session-project-note');
                """)
        }
        let db = try AppDatabase(queue)
        let columns = try db.writer.read { try $0.columns(in: "session").map(\.name) }
        #expect(columns.contains("note"))
        #expect(!columns.contains("projectTitle"))
    }
}

struct TimestampStorageTests {
    @Test func datesAreStoredAsLocalTimeWithOffsetNotEpochOrUTC() throws {
        let db = try AppDatabase.inMemory()
        let g = try db.importStudents([.init(mssv: "1", fullName: "An", className: "", projectTitle: "", email: "")],
                                      intoNewGroupNamed: "A")
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let s = try db.insertSession(Session(studentId: db.progress(groupId: g)[0].id, date: date, audioPath: "a.m4a"))

        let stored = try db.writer.read { try String.fetchOne($0, sql: "SELECT date FROM session WHERE id = ?", arguments: [s.id!]) }
        #expect(stored == DBTimestamp.string(date))
        #expect(stored?.wholeMatch(of: /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}|.*Z/) != nil)

        let loaded = try #require(try db.session(id: s.id!))
        #expect(abs(loaded.date.timeIntervalSince(date)) < 0.001)
        #expect(try db.progress(groupId: g)[0].sessionDates.count == 1)
    }

    @Test func utteranceTimesAreSecondsInJSON() throws {
        let json = try JSONEncoder().encode(Utterance(speaker: "A", text: "x", start: 12.5, end: 14))
        #expect(String(decoding: json, as: UTF8.self).contains("\"start\":12.5"))
    }
}

struct ClaudeCLISummarizerTests {
    @Test func acceptsUnknownTeacherSpeaker() throws {
        let inner = ###"{"teacher_speaker": null, "summary_markdown": "## Đã làm được\nBản ghi quá ngắn."}"###
        let envelope = try JSONSerialization.data(withJSONObject: ["type": "result", "result": inner])
        let result = try ClaudeCLISummarizer.parse(cliOutput: envelope)
        #expect(result.teacherSpeaker == nil)
        #expect(result.summaryMarkdown.hasPrefix("## Đã làm được"))
    }

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

struct SonioxEngineTests {
    @Test func groupsTokensBySpeakerAndRelabelsInOrderOfAppearance() {
        let tokens: [SonioxEngine.Token] = [
            .init(text: "Chào", startMs: 100, endMs: 300, speaker: "2"),
            .init(text: " em", startMs: 300, endMs: 500, speaker: "2"),
            .init(text: " Dạ", startMs: 900, endMs: 1100, speaker: "1"),
            .init(text: " chào thầy", startMs: 1100, endMs: 1600, speaker: "1"),
            .init(text: " Tuần", startMs: 2000, endMs: 2250, speaker: "2"),
        ]
        let utterances = SonioxEngine.utterances(from: tokens)
        #expect(utterances == [
            Utterance(speaker: "A", text: "Chào em", start: 0.1, end: 0.5),
            Utterance(speaker: "B", text: "Dạ chào thầy", start: 0.9, end: 1.6),
            Utterance(speaker: "A", text: "Tuần", start: 2.0, end: 2.25),
        ])
    }

    @Test func dropsWhitespaceOnlyUtterances() {
        let tokens: [SonioxEngine.Token] = [
            .init(text: " ", startMs: 0, endMs: 10, speaker: "1"),
            .init(text: "Ok", startMs: 20, endMs: 40, speaker: "2"),
        ]
        #expect(SonioxEngine.utterances(from: tokens).map(\.text) == ["Ok"])
    }

    @Test func decodesTranscriptWithStringOrNumericSpeaker() throws {
        let json = #"{"id":"x","text":"a b","tokens":[{"text":"a","start_ms":0,"end_ms":10,"confidence":0.9,"speaker":"1"},{"text":" b","start_ms":10,"end_ms":20,"confidence":0.9,"speaker":2}]}"#
        let transcript = try JSONDecoder().decode(SonioxEngine.Transcript.self, from: Data(json.utf8))
        #expect(transcript.tokens.map(\.speaker) == ["1", "2"])
        #expect(SonioxEngine.utterances(from: transcript.tokens).map(\.speaker) == ["A", "B"])
    }

    @Test func decodesJobError() throws {
        let json = #"{"id":"t","status":"error","error_type":"invalid_audio","error_message":"Bad file"}"#
        let job = try JSONDecoder().decode(SonioxEngine.Transcription.self, from: Data(json.utf8))
        #expect(job.status == "error" && job.errorMessage == "Bad file")
    }
}

struct SessionCalendarTests {
    private func date(_ s: String) -> Date { DBTimestamp.date(s)! }

    @Test func showsAtLeastMinimumWeeksEndingThisWeek() {
        let now = date("2026-09-30 10:00:00.000+07:00") // Wednesday
        let weeks = WeekCalendar.weekStarts(covering: [], now: now, minimumCount: 3)
        #expect(weeks.count == 3)
        #expect(weeks.last == WeekCalendar.startOfWeek(now))
        #expect(weeks.allSatisfy { WeekCalendar.calendar.component(.weekday, from: $0) == 2 }) // Mondays
    }

    @Test func extendsBackToOldestSession() {
        let now = date("2026-09-30 10:00:00.000+07:00")
        let old = date("2026-06-03 09:00:00.000+07:00")
        let weeks = WeekCalendar.weekStarts(covering: [old, now], now: now, minimumCount: 2)
        #expect(weeks.first == WeekCalendar.startOfWeek(old))
        #expect(weeks.last == WeekCalendar.startOfWeek(now))
        #expect(Set(weeks).count == weeks.count)
    }
}

struct MonthGridTests {
    private func date(_ s: String) -> Date { DBTimestamp.date(s)! }

    @Test func coversWholeMondayToSundayWeeksOfTheMonth() {
        // September 2026: starts Tuesday 1st, ends Wednesday 30th → Mon 31 Aug … Sun 4 Oct = 5 weeks.
        let days = WeekCalendar.monthGridDays(containing: date("2026-09-30 10:00:00.000+07:00"))
        let cal = WeekCalendar.calendar
        #expect(days.count == 35)
        #expect(cal.dateComponents([.month, .day], from: days.first!) == DateComponents(month: 8, day: 31))
        #expect(cal.dateComponents([.month, .day], from: days.last!) == DateComponents(month: 10, day: 4))
        #expect(cal.component(.weekday, from: days.first!) == 2)
    }

    @Test func monthStartingOnMondayHasNoLeadingDays() {
        // June 2026 starts on a Monday and ends on a Tuesday → 5 weeks.
        let days = WeekCalendar.monthGridDays(containing: date("2026-06-15 12:00:00.000+07:00"))
        #expect(days.first == WeekCalendar.startOfMonth(date("2026-06-15 12:00:00.000+07:00")))
        #expect(days.count == 35)
    }
}

struct ReportCountTests {
    private func date(_ s: String) -> Date { DBTimestamp.date(s)! }
    private func progress(_ id: Int64, _ dates: [String]) -> StudentProgress {
        StudentProgress(student: Student(id: id, groupId: 1, mssv: "\(id)", fullName: "S\(id)", className: "", projectTitle: "", email: ""),
                        sessionDates: dates.map(date))
    }

    @Test func countsEachStudentOncePerDay() {
        let counts = WeekCalendar.studentsPerDay([
            progress(1, ["2026-09-28 09:00:00.000+07:00", "2026-09-28 15:00:00.000+07:00", "2026-09-30 10:00:00.000+07:00"]),
            progress(2, ["2026-09-28 23:59:00.000+07:00"]),
            progress(3, []),
        ])
        let cal = WeekCalendar.calendar
        #expect(counts[cal.startOfDay(for: date("2026-09-28 12:00:00.000+07:00"))] == 2)
        #expect(counts[cal.startOfDay(for: date("2026-09-30 12:00:00.000+07:00"))] == 1)
        #expect(counts.count == 2)
    }
}

struct SpeakerRoleTests {
    private func session(teacher: String?) -> Session {
        var s = Session(studentId: 1, date: .now, audioPath: "a.m4a")
        s.utterances = [
            Utterance(speaker: "A", text: "x", start: 0, end: 1),
            Utterance(speaker: "B", text: "y", start: 1, end: 2),
            Utterance(speaker: "A", text: "z", start: 2, end: 3),
        ]
        s.teacherSpeaker = teacher
        return s
    }

    @Test func labelsTeacherAndStudent() {
        let s = session(teacher: "B")
        #expect(s.roleName(of: "B") == "Teacher")
        #expect(s.roleName(of: "A") == "Student")
        #expect(session(teacher: nil).roleName(of: "A") == "Speaker A")
    }

    @Test func swapPicksTheOtherSpeaker() {
        #expect(session(teacher: "A").swappedTeacherSpeaker == "B")
        #expect(session(teacher: "B").swappedTeacherSpeaker == "A")
    }
}
