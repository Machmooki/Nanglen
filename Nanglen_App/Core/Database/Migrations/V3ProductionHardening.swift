import Foundation
import GRDB

/// v3: production hardening of the local layer. SQLite stays a disposable cache, an outbox for photos
/// and device state — never a source of truth.
///
/// - Drops the v1 legacy archive (`check_ins`, `favorites`, `venues`, `app_identity`), children first.
/// - Rebuilds `cached_venues` (cache is disposable) with `payload_version` and `last_accessed_at` for LRU pruning.
/// - Adds `cached_venue_details` for offline venue detail (no per-user fields are ever stored).
/// - Moves the server config out of `local_drafts` into `app_kv`, then rebuilds `local_drafts`
///   scoped by `user_id`. Old drafts had no owner and are discarded.
/// - Adds `pending_uploads`: photos whose review/submission was published but whose upload failed offline.
nonisolated enum V3ProductionHardening {
    static let identifier = "v3_production_hardening"
    /// Key of the server config row, both in the old `local_drafts` and in `app_kv`.
    static let remoteConfigKey = "remote_config.v1"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            // v1 legacy archive, in foreign-key order.
            for table in ["check_ins", "favorites", "venues", "app_identity"] {
                try db.execute(sql: "DROP TABLE IF EXISTS \(table)")
            }

            // Device state that survives "Clear cache" and sign-out.
            try db.create(table: "app_kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .blob).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.execute(
                sql: "INSERT INTO app_kv (key, value, updated_at) SELECT key, payload, updated_at FROM local_drafts WHERE key = ?",
                arguments: [remoteConfigKey])

            // Drafts are per user now; ownerless v2 drafts are dropped (app not released yet).
            try db.execute(sql: "DROP TABLE IF EXISTS local_drafts")
            try db.create(table: "local_drafts") { t in
                t.column("user_id", .text).notNull()
                t.column("key", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("payload_version", .integer).notNull()
                t.column("updated_at", .datetime).notNull()
                t.primaryKey(["user_id", "key"])
            }

            // Venue cards: rebuilt, the old rows are only a cache.
            try db.execute(sql: "DROP TABLE IF EXISTS cached_venues")
            try db.create(table: "cached_venues") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("payload", .blob).notNull()
                t.column("payload_version", .integer).notNull()
                t.column("cached_at", .datetime).notNull()
                t.column("last_accessed_at", .datetime).notNull()
            }
            try db.create(index: "idx_cached_venues_coordinate", on: "cached_venues", columns: ["latitude", "longitude"])
            try db.create(index: "idx_cached_venues_cached_at", on: "cached_venues", columns: ["cached_at"])
            try db.create(index: "idx_cached_venues_last_accessed_at", on: "cached_venues", columns: ["last_accessed_at"])

            // Public venue detail for offline viewing. Never contains favorite/review/manager state.
            try db.create(table: "cached_venue_details") { t in
                t.primaryKey("venue_id", .text)
                t.column("payload", .blob).notNull()
                t.column("payload_version", .integer).notNull()
                t.column("cached_at", .datetime).notNull()
                t.column("last_accessed_at", .datetime).notNull()
            }
            try db.create(index: "idx_cached_venue_details_cached_at", on: "cached_venue_details", columns: ["cached_at"])
            try db.create(index: "idx_cached_venue_details_last_accessed_at", on: "cached_venue_details", columns: ["last_accessed_at"])

            // Photo outbox. `local_path` is a file name inside Application Support/PendingUploads
            // (the container path changes between installs, so absolute paths are not stored).
            // `venue_id` lets the detail screen refresh once a review photo lands.
            try db.create(table: "pending_uploads") { t in
                t.primaryKey("id", .text)
                t.column("user_id", .text).notNull()
                t.column("kind", .text).notNull().check(sql: "kind IN ('review_photo', 'submission_photo')")
                t.column("target_id", .text).notNull()
                t.column("venue_id", .text)
                t.column("local_path", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
                t.column("next_attempt_at", .datetime).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_pending_uploads_next_attempt_at", on: "pending_uploads", columns: ["next_attempt_at"])
            try db.create(index: "idx_pending_uploads_user", on: "pending_uploads", columns: ["user_id"])
        }
    }
}
