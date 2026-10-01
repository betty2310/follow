import Foundation
import GRDB
import SwiftUI

/// The only place that talks to SQLite. Views read through async observations and write through methods here.
/// File: ~/Documents/ProjectRecord/ProjectRecord.sqlite (docs/DECISIONS.md D14, D19).
struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static func onDisk(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabasePool(path: url.path, configuration: config))
    }

    /// Empty in-memory database for tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    // MARK: Schema

    /// Append new migrations; never edit a migration that has shipped.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "studentGroup") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "student") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("groupId", .integer).notNull().indexed()
                    .references("studentGroup", onDelete: .cascade)
                t.column("mssv", .text).notNull()
                t.column("fullName", .text).notNull()
                t.column("className", .text).notNull().defaults(to: "")
                t.column("projectTitle", .text).notNull().defaults(to: "")
                t.column("email", .text).notNull().defaults(to: "")
                t.uniqueKey(["groupId", "mssv"])
            }
            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("studentId", .integer).notNull().indexed()
                    .references("student", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("audioPath", .text).notNull()
                t.column("status", .text).notNull()
                t.column("errorMessage", .text)
                t.column("transcriptEngine", .text)
                t.column("utterances", .text).notNull().defaults(to: "[]")
                t.column("teacherSpeaker", .text)
                t.column("summaryMarkdown", .text)
            }
        }
        migrator.registerMigration("v2-local-timestamps") { db in
            // v1 stored GRDB's default UTC text ("2026-09-30 03:37:39.175"). Rewrite as local time + offset (D22).
            for (table, column) in [("studentGroup", "createdAt"), ("session", "date")] {
                let rows = try Row.fetchAll(db, sql: "SELECT id, \(column) AS value FROM \(table)")
                for row in rows {
                    let old: Date = row["value"]
                    try db.execute(sql: "UPDATE \(table) SET \(column) = ? WHERE id = ?",
                                   arguments: [DBTimestamp.string(old), row["id"] as Int64])
                }
            }
        }
        migrator.registerMigration("v3-group-archive") { db in
            try db.alter(table: "studentGroup") { t in t.add(column: "archivedAt", .datetime) }
        }
        return migrator
    }
}

// MARK: - Reads

extension AppDatabase {
    /// Every group (newest first, archived included) with its students' progress, in one consistent snapshot.
    func observeGroups() -> AsyncValueObservation<[GroupProgress]> {
        ValueObservation
            .tracking { db in try Self.groups(db) }
            .values(in: writer)
    }

    func groups() throws -> [GroupProgress] {
        try writer.read { db in try Self.groups(db) }
    }

    func observeSessions(studentId: Int64) -> AsyncValueObservation<[Session]> {
        ValueObservation
            .tracking { db in
                try Session.filter(Session.Columns.studentId == studentId).order(Session.Columns.date.desc).fetchAll(db)
            }
            .values(in: writer)
    }

    func observeStudent(id: Int64) -> AsyncValueObservation<Student?> {
        ValueObservation.tracking { db in try Student.fetchOne(db, id: id) }.values(in: writer)
    }

    func group(id: Int64) throws -> StudentGroup? {
        try writer.read { db in try StudentGroup.fetchOne(db, id: id) }
    }

    func progress(groupId: Int64) throws -> [StudentProgress] {
        try writer.read { db in try Self.progress(db, groupId: groupId) }
    }

    private static func groups(_ db: Database) throws -> [GroupProgress] {
        let groups = try StudentGroup.order(StudentGroup.Columns.createdAt.desc).fetchAll(db)
        let progress = Dictionary(grouping: try Self.progress(db, groupId: nil), by: \.student.groupId)
        return groups.map { GroupProgress(group: $0, students: progress[$0.id!] ?? []) }
    }

    /// Students sorted by name, with their session dates. `groupId == nil` means all groups.
    private static func progress(_ db: Database, groupId: Int64?) throws -> [StudentProgress] {
        var request = Student.all()
        var sql = "SELECT session.studentId, session.date FROM session JOIN student ON student.id = session.studentId"
        var arguments: StatementArguments = []
        if let groupId {
            request = request.filter(Student.Columns.groupId == groupId)
            sql += " WHERE student.groupId = ?"
            arguments = [groupId]
        }
        let students = try request.fetchAll(db)
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        var dates: [Int64: [Date]] = [:]
        for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
            guard let date = DBTimestamp.date(row["date"]) else { continue }
            dates[row["studentId"], default: []].append(date)
        }
        return students.map { StudentProgress(student: $0, sessionDates: dates[$0.id!] ?? []) }
    }
}

// MARK: - Writes

extension AppDatabase {
    struct ImportPlan: Equatable, Sendable {
        var new = 0
        var updated = 0
        var unchanged = 0
    }

    @discardableResult
    func createGroup(name: String) throws -> StudentGroup {
        try writer.write { db in
            var group = StudentGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            try group.insert(db)
            return group
        }
    }

    func renameGroup(id: Int64, to name: String) throws {
        try writer.write { db in
            guard var group = try StudentGroup.fetchOne(db, id: id) else { return }
            group.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try group.update(db)
        }
    }

    /// Archiving only hides the group in the sidebar's Archived section; students and sessions are kept.
    func setGroupArchived(id: Int64, _ archived: Bool) throws {
        try writer.write { db in
            guard var group = try StudentGroup.fetchOne(db, id: id) else { return }
            group.archivedAt = archived ? .now : nil
            try group.update(db)
        }
    }

    /// Deletes the group with its students and sessions (FK cascade).
    /// Returns the deleted sessions' audio paths (relative to `AppPaths.root`) so the caller can remove the files.
    @discardableResult
    func deleteGroup(id: Int64) throws -> [String] {
        try writer.write { db in
            let paths = try String.fetchAll(db, sql: """
                SELECT session.audioPath FROM session
                JOIN student ON student.id = session.studentId
                WHERE student.groupId = ?
                """, arguments: [id])
            try StudentGroup.deleteOne(db, id: id)
            return paths
        }
    }

    /// What `importStudents` would do, without writing. `groupId == nil` means a new group.
    func planImport(_ rows: [StudentImporter.Row], into groupId: Int64?) throws -> ImportPlan {
        try writer.read { db in try Self.apply(rows, groupId: groupId, db: db, dryRun: true) }
    }

    /// Adds new MSSVs, updates existing ones in the group, never deletes (docs/DECISIONS.md D20).
    @discardableResult
    func importStudents(_ rows: [StudentImporter.Row], into groupId: Int64) throws -> ImportPlan {
        try writer.write { db in try Self.apply(rows, groupId: groupId, db: db, dryRun: false) }
    }

    /// Creates the group and imports into it in one transaction. Returns the new group's id.
    func importStudents(_ rows: [StudentImporter.Row], intoNewGroupNamed name: String) throws -> Int64 {
        try writer.write { db in
            var group = StudentGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            try group.insert(db)
            try Self.apply(rows, groupId: group.id!, db: db, dryRun: false)
            return group.id!
        }
    }

    @discardableResult
    private static func apply(_ rows: [StudentImporter.Row], groupId: Int64?, db: Database, dryRun: Bool) throws -> ImportPlan {
        var existing: [String: Student] = [:]
        if let groupId {
            for s in try Student.filter(Student.Columns.groupId == groupId).fetchAll(db) { existing[s.mssv] = s }
        }
        var plan = ImportPlan()
        for row in rows {
            if var student = existing[row.mssv] {
                let before = student
                student.fullName = row.fullName
                if !row.className.isEmpty { student.className = row.className }
                if !row.projectTitle.isEmpty { student.projectTitle = row.projectTitle }
                if !row.email.isEmpty { student.email = row.email }
                if student == before { plan.unchanged += 1; continue }
                plan.updated += 1
                if !dryRun { try student.update(db) }
                existing[row.mssv] = student
            } else {
                plan.new += 1
                guard !dryRun, let groupId else { continue }
                var student = Student(groupId: groupId, mssv: row.mssv, fullName: row.fullName,
                                      className: row.className, projectTitle: row.projectTitle, email: row.email)
                try student.insert(db)
                existing[row.mssv] = student
            }
        }
        return plan
    }

    func insertSession(_ session: Session) throws -> Session {
        try writer.write { db in
            var session = session
            try session.insert(db)
            return session
        }
    }

    func deleteSession(id: Int64) throws {
        _ = try writer.write { db in try Session.deleteOne(db, id: id) }
    }

    func session(id: Int64) throws -> Session? {
        try writer.read { db in try Session.fetchOne(db, id: id) }
    }

    func student(id: Int64) throws -> Student? {
        try writer.read { db in try Student.fetchOne(db, id: id) }
    }

    /// Read-modify-write a session in one transaction.
    func updateSession(id: Int64, _ change: @Sendable (inout Session) -> Void) throws {
        try writer.write { db in
            guard var session = try Session.fetchOne(db, id: id) else { return }
            change(&session)
            try session.update(db)
        }
    }
}

// MARK: - SwiftUI environment

extension EnvironmentValues {
    @Entry var appDatabase: AppDatabase = try! .inMemory()
}
