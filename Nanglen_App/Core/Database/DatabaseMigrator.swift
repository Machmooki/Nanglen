import Foundation
import GRDB

/// Central list of schema migrations. Migrations are append-only: never edit a
/// shipped migration, add a new one (e.g. `V2_...`) instead.
nonisolated enum AppDatabaseMigrator {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        V1InitialSchema.register(in: &migrator)
        V2CacheAndLegacyArchive.register(in: &migrator)
        return migrator
    }
}
