import Foundation
import GRDB

/// A cached card plus when it was fetched, so the UI can label stale data honestly.
nonisolated struct CachedVenue: Hashable, Sendable {
    var venue: VenueSummary
    var cachedAt: Date
}

/// GRDB-backed read cache and local drafts. Never authoritative: every write the user cares
/// about goes to the backend first; the cache only mirrors confirmed server data.
nonisolated final class LocalCache: Sendable {
    private let writer: any DatabaseWriter

    init(database: DatabaseManager) {
        writer = database.writer
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func arguments(_ values: [any DatabaseValueConvertible]) -> StatementArguments {
        StatementArguments(values.map { Optional($0) })
    }

    // MARK: Venues

    func storeVenues(_ venues: [VenueSummary], at date: Date) async throws {
        guard !venues.isEmpty else { return }
        let rows = try venues.map { venue -> StatementArguments in
            var stored = venue
            stored.distanceMeters = nil // distance depends on the origin; recomputed on read
            stored.rankScore = nil
            let values: [any DatabaseValueConvertible] = [venue.id.uuidString, venue.name, venue.category.rawValue, venue.coordinate.latitude,
                                                          venue.coordinate.longitude, try Self.encoder.encode(stored), date]
            return Self.arguments(values)
        }
        try await writer.write { db in
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO cached_venues (id, name, category, latitude, longitude, payload, cached_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, category = excluded.category,
                        latitude = excluded.latitude, longitude = excluded.longitude,
                        payload = excluded.payload, cached_at = excluded.cached_at
                    """,
                    arguments: row)
            }
        }
    }

    /// Bounded cache query for offline Explore. Filtering by radius uses a bounding box in SQL and
    /// exact distance in Swift.
    func cachedVenues(near origin: GeoPoint?, radiusMeters: Double, category: VenueCategory?, text: String?,
                      notOlderThan oldest: Date, limit: Int = 100) async throws -> [CachedVenue] {
        var conditions = ["cached_at >= ?"]
        var arguments: [any DatabaseValueConvertible] = [oldest]
        if let category {
            conditions.append("category = ?")
            arguments.append(category.rawValue)
        }
        if let origin, (text ?? "").isEmpty {
            let latDelta = radiusMeters / 111_000
            let lonDelta = radiusMeters / max(111_000 * cos(origin.latitude * .pi / 180), 1)
            conditions.append("latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?")
            arguments += [origin.latitude - latDelta, origin.latitude + latDelta, origin.longitude - lonDelta, origin.longitude + lonDelta]
        }
        if let text, !text.isEmpty {
            conditions.append("name LIKE ?")
            arguments.append("%\(text)%")
        }
        let statementArguments = Self.arguments(arguments)
        let sql = "SELECT payload, cached_at FROM cached_venues WHERE \(conditions.joined(separator: " AND ")) LIMIT \(max(1, min(limit, 200)))"
        let rows = try await writer.read { db in
            try Row.fetchAll(db, sql: sql, arguments: statementArguments)
                .map { (payload: $0["payload"] as Data, cachedAt: $0["cached_at"] as Date) }
        }
        return rows.compactMap { row in
            guard var venue = try? Self.decoder.decode(VenueSummary.self, from: row.payload) else { return nil }
            venue.distanceMeters = origin.map { venue.coordinate.distance(to: $0) }
            return CachedVenue(venue: venue, cachedAt: row.cachedAt)
        }
    }

    func cachedVenues(ids: [UUID]) async throws -> [UUID: CachedVenue] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT payload, cached_at FROM cached_venues WHERE id IN (\(placeholders))",
                             arguments: Self.arguments(ids.map(\.uuidString)))
                .map { (payload: $0["payload"] as Data, cachedAt: $0["cached_at"] as Date) }
        }
        var result: [UUID: CachedVenue] = [:]
        for row in rows {
            if let venue = try? Self.decoder.decode(VenueSummary.self, from: row.payload) {
                result[venue.id] = CachedVenue(venue: venue, cachedAt: row.cachedAt)
            }
        }
        return result
    }

    func pruneVenues(olderThan date: Date) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM cached_venues WHERE cached_at < ?", arguments: [date])
        }
    }

    // MARK: Favorites

    func storeFavoriteIDs(_ ids: [UUID], userID: UUID, at date: Date) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM cached_favorites WHERE user_id = ?", arguments: [userID.uuidString])
            for (position, id) in ids.enumerated() {
                try db.execute(sql: "INSERT INTO cached_favorites (user_id, venue_id, position, cached_at) VALUES (?, ?, ?, ?)",
                               arguments: [userID.uuidString, id.uuidString, position, date])
            }
        }
    }

    func cachedFavoriteIDs(userID: UUID) async throws -> [UUID] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT venue_id FROM cached_favorites WHERE user_id = ? ORDER BY position",
                                arguments: [userID.uuidString])
        }.compactMap(UUID.init(uuidString:))
    }

    // MARK: Drafts

    func saveDraft<T: Encodable & Sendable>(_ value: T, key: String, at date: Date = Date()) async throws {
        let data = try Self.encoder.encode(value)
        try await writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO local_drafts (key, payload, updated_at) VALUES (?, ?, ?)",
                           arguments: [key, data, date])
        }
    }

    func draft<T: Decodable & Sendable>(_ type: T.Type, key: String) async throws -> T? {
        let data = try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM local_drafts WHERE key = ?", arguments: [key])
        }
        return try data.map { try Self.decoder.decode(T.self, from: $0) }
    }

    func deleteDraft(key: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM local_drafts WHERE key = ?", arguments: [key])
        }
    }

    // MARK: Remote config

    static let remoteConfigKey = "remote_config.v1"

    /// Synchronous on purpose: read once at launch, before the first screen, so it already uses server limits.
    func cachedRemoteConfig() -> RemoteConfigValues? {
        let data = try? writer.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM local_drafts WHERE key = ?", arguments: [Self.remoteConfigKey])
        }
        return data.flatMap { try? Self.decoder.decode(RemoteConfigValues.self, from: $0) }
    }

    func storeRemoteConfig(_ values: RemoteConfigValues) async throws {
        try await saveDraft(values, key: Self.remoteConfigKey)
    }

    // MARK: Maintenance

    /// Clears cached content and drafts. The server config is kept: it isn't personal data and the app needs it offline.
    func clearAll() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM cached_venues")
            try db.execute(sql: "DELETE FROM cached_favorites")
            try db.execute(sql: "DELETE FROM local_drafts WHERE key <> ?", arguments: [Self.remoteConfigKey])
        }
    }

    func cachedVenueCount() async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_venues") ?? 0 }
    }
}
