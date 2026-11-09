import Foundation
import GRDB

/// v2: the cloud is now the source of truth. SQLite becomes a bounded read cache plus local drafts.
///
/// The v1 tables (`check_ins`, `venues`, `favorites`, `app_identity`) held device-only crowd/noise
/// reports and MapKit places. They are **kept as-is and no longer read or written** (legacy archive):
/// old reports are not reinterpreted as reviews, and old favorites referenced MapKit places, not
/// approved venues. They are not renamed because GRDB runs migrations with `legacy_alter_table`,
/// which would leave the v1 foreign keys pointing at the old names.
nonisolated enum V2CacheAndLegacyArchive {
    static let identifier = "v2_cache_and_legacy_archive"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            // Approved venue cards (JSON payload of `VenueSummary`) with columns for bounded queries.
            try db.create(table: "cached_venues") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("payload", .blob).notNull()
                t.column("cached_at", .datetime).notNull()
            }
            try db.create(index: "idx_cached_venues_coordinate", on: "cached_venues", columns: ["latitude", "longitude"])
            try db.create(index: "idx_cached_venues_cached_at", on: "cached_venues", columns: ["cached_at"])

            // The signed-in user's favorite ids, for offline Saved display. Server is authoritative.
            try db.create(table: "cached_favorites") { t in
                t.column("user_id", .text).notNull()
                t.column("venue_id", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("cached_at", .datetime).notNull()
                t.primaryKey(["user_id", "venue_id"])
            }

            // Unsent drafts (review composer, add place). Never shown as published.
            try db.create(table: "local_drafts") { t in
                t.primaryKey("key", .text)
                t.column("payload", .blob).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }
    }
}
