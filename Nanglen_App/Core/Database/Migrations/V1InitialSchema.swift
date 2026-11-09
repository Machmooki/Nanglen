import Foundation
import GRDB

/// v1: identity, venues cache, check-in reports and favorites.
nonisolated enum V1InitialSchema {
    static let identifier = "v1_initial_schema"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            // Single-row table holding this device's guest identity.
            try db.create(table: "app_identity") { t in
                t.primaryKey("id", .integer).check(sql: "id = 1")
                t.column("guest_id", .text).notNull().unique()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "venues") { t in
                t.primaryKey("id", .text)
                t.column("external_place_id", .text).notNull().unique()
                t.column("name", .text).notNull().check(sql: "length(name) > 0")
                t.column("address", .text)
                t.column("latitude", .double).notNull().check(sql: "latitude BETWEEN -90 AND 90")
                t.column("longitude", .double).notNull().check(sql: "longitude BETWEEN -180 AND 180")
                t.column("category", .text).notNull()
                    .check(sql: "category IN ('cafe', 'library', 'coworking', 'study_space', 'other')")
                // NULL = unknown for every amenity column.
                t.column("price_level", .integer).check(sql: "price_level BETWEEN 0 AND 3")
                t.column("has_wifi", .boolean)
                t.column("has_power_outlet", .boolean)
                t.column("opening_hours", .text)
                t.column("phone_number", .text)
                t.column("website_url", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "idx_venues_coordinate", on: "venues", columns: ["latitude", "longitude"])
            try db.create(index: "idx_venues_name", on: "venues", columns: ["name"])

            try db.create(table: "check_ins") { t in
                t.primaryKey("id", .text)
                t.column("venue_id", .text).notNull()
                    .references("venues", onDelete: .cascade)
                t.column("guest_id", .text).notNull()
                    .references("app_identity", column: "guest_id", onDelete: .cascade, onUpdate: .cascade)
                t.column("crowd_level", .text).check(sql: "crowd_level IN ('low', 'medium', 'high')")
                t.column("noise_level", .text).check(sql: "noise_level IN ('quiet', 'moderate', 'loud')")
                t.column("seat_availability", .text).check(sql: "seat_availability IN ('available', 'limited', 'full')")
                t.column("wifi_status", .text).notNull().defaults(to: "unknown")
                    .check(sql: "wifi_status IN ('available', 'unavailable', 'unknown')")
                t.column("power_status", .text).notNull().defaults(to: "unknown")
                    .check(sql: "power_status IN ('available', 'unavailable', 'unknown')")
                t.column("note", .text)
                t.column("is_verified", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("expires_at", .datetime).notNull()
                t.check(sql: "expires_at > created_at")
            }
            try db.create(index: "idx_check_ins_venue_created", on: "check_ins", columns: ["venue_id", "created_at"])
            try db.create(index: "idx_check_ins_guest", on: "check_ins", columns: ["guest_id"])
            try db.create(index: "idx_check_ins_expires", on: "check_ins", columns: ["expires_at"])

            try db.create(table: "favorites") { t in
                t.primaryKey("id", .text)
                t.column("venue_id", .text).notNull()
                    .references("venues", onDelete: .cascade)
                t.column("guest_id", .text).notNull()
                    .references("app_identity", column: "guest_id", onDelete: .cascade, onUpdate: .cascade)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["venue_id", "guest_id"])
            }
            try db.create(index: "idx_favorites_guest_created", on: "favorites", columns: ["guest_id", "created_at"])
        }
    }
}
