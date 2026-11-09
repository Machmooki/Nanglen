import Foundation
import GRDB

/// Owns the SQLite connection and guarantees the schema is migrated before
/// anyone reads or writes. Repositories receive `writer` — UI code never sees it.
nonisolated final class DatabaseManager: Sendable {
    let writer: any DatabaseWriter

    /// Wraps an existing GRDB writer and runs all pending migrations.
    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try AppDatabaseMigrator.makeMigrator().migrate(writer)
    }

    static func configuration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "Nanglen"
        return config
    }

    /// The app's persistent database in Application Support.
    /// - Parameter reset: deletes the existing file first (UI tests only).
    static func onDisk(fileName: String = "nanglen.sqlite", reset: Bool = false) throws -> DatabaseManager {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Database", isDirectory: true)
        if reset { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try at(path: directory.appendingPathComponent(fileName).path)
    }

    /// A database file at an explicit path (used by persistence tests to reopen).
    static func at(path: String) throws -> DatabaseManager {
        let pool = try DatabasePool(path: path, configuration: configuration())
        return try DatabaseManager(writer: pool)
    }

    /// Throw-away in-memory database for tests and as a last-resort fallback.
    static func inMemory() throws -> DatabaseManager {
        let queue = try DatabaseQueue(configuration: configuration())
        return try DatabaseManager(writer: queue)
    }

    /// Names of user tables — used to verify migrations.
    func tableNames() throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name")
        }
    }
}
