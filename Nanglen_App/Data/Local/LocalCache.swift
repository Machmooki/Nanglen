import Foundation
import GRDB
import os

/// A cached card plus when it was fetched, so the UI can label stale data honestly.
nonisolated struct CachedVenue: Hashable, Sendable {
    var venue: VenueSummary
    var cachedAt: Date
}

/// A cached public venue detail. Per-user fields are always empty (`isFavorite == false`,
/// `isManagedByMe == false`, `myReview == nil`); callers fill what they know.
nonisolated struct CachedVenueDetail: Hashable, Sendable {
    var detail: VenueDetail
    var cachedAt: Date
}

/// A value stored as a JSON payload. Bump `payloadVersion` whenever the encoded shape changes
/// incompatibly: rows written with another version are deleted on read instead of being misread.
nonisolated protocol LocalPayload: Codable, Sendable {
    static var payloadVersion: Int { get }
}

nonisolated extension VenueSummary: LocalPayload {
    static var payloadVersion: Int { 1 }
}

nonisolated extension ReviewDraft: LocalPayload {
    static var payloadVersion: Int { 1 }
}

nonisolated extension VenueSubmissionDraft: LocalPayload {
    static var payloadVersion: Int { 1 }
}

/// What `cached_venue_details` stores: the public part of `VenueDetail` only.
nonisolated struct VenueDetailPayload: LocalPayload, Hashable {
    static var payloadVersion: Int { 1 }

    var summary: VenueSummary
    var description: String?
    var websiteURL: URL?
    var phoneNumber: String?
    var detailsSource: String?
    var appleMapsID: String?
    var ratingDistribution: [Int]?
    var lastReviewAt: Date?
    var tagCounts: [TagCount]
    var photoPaths: [String]
    var panoramaPath: String?

    init(_ detail: VenueDetail) {
        var summary = detail.summary
        summary.distanceMeters = nil
        summary.rankScore = nil
        self.summary = summary
        description = detail.description
        websiteURL = detail.websiteURL
        phoneNumber = detail.phoneNumber
        detailsSource = detail.detailsSource
        appleMapsID = detail.appleMapsID
        ratingDistribution = detail.ratingDistribution
        lastReviewAt = detail.lastReviewAt
        tagCounts = detail.tagCounts
        photoPaths = detail.photoPaths
        panoramaPath = detail.panoramaPath
    }

    /// The detail with every per-user field cleared.
    var detail: VenueDetail {
        VenueDetail(summary: summary, description: description, websiteURL: websiteURL, phoneNumber: phoneNumber,
                    detailsSource: detailsSource, appleMapsID: appleMapsID, ratingDistribution: ratingDistribution,
                    lastReviewAt: lastReviewAt, tagCounts: tagCounts, photoPaths: photoPaths,
                    isFavorite: false, isManagedByMe: false, myReview: nil, panoramaPath: panoramaPath)
    }
}

nonisolated enum PendingUploadKind: String, Hashable, Sendable {
    case reviewPhoto = "review_photo"
    case submissionPhoto = "submission_photo"
}

/// A photo whose review/submission was published but whose upload failed for a network reason.
nonisolated struct PendingUpload: Hashable, Sendable {
    var id: UUID
    var userID: UUID
    var kind: PendingUploadKind
    /// Review revision id or submission id the photo attaches to.
    var targetID: UUID
    /// The reviewed venue, so the detail screen can refresh (nil for submissions).
    var venueID: UUID?
    /// File name inside the pending-uploads directory.
    var fileName: String
    var mimeType: String
    var attempts: Int = 0
    var lastError: String?
    var nextAttemptAt: Date
    var createdAt: Date
}

/// GRDB-backed read cache, local drafts, photo outbox and small device state. Never authoritative:
/// every write the user cares about goes to the backend first; the cache only mirrors confirmed server data.
nonisolated final class LocalCache: Sendable {
    private let writer: any DatabaseWriter
    private static let logger = Logger(subsystem: "Mach.Nanglen-App", category: "LocalCache")

    init(database: DatabaseManager) {
        writer = database.writer
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func arguments(_ values: [any DatabaseValueConvertible]) -> StatementArguments {
        StatementArguments(values.map { Optional($0) })
    }

    /// Decodes a payload, or returns nil when its version or shape doesn't match (the caller deletes the row).
    private static func decode<T: LocalPayload>(_ type: T.Type, payload: Data, version: Int) -> T? {
        guard version == T.payloadVersion else { return nil }
        return try? decoder.decode(T.self, from: payload)
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    // MARK: Venues

    func storeVenues(_ venues: [VenueSummary], at date: Date) async throws {
        guard !venues.isEmpty else { return }
        let rows = try venues.map { venue -> StatementArguments in
            var stored = venue
            stored.distanceMeters = nil // distance depends on the origin; recomputed on read
            stored.rankScore = nil
            let values: [any DatabaseValueConvertible] = [
                venue.id.uuidString, venue.name, venue.category.rawValue, venue.coordinate.latitude,
                venue.coordinate.longitude, try Self.encoder.encode(stored), VenueSummary.payloadVersion, date, date,
            ]
            return Self.arguments(values)
        }
        try await writer.write { db in
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO cached_venues (id, name, category, latitude, longitude, payload, payload_version, cached_at, last_accessed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, category = excluded.category,
                        latitude = excluded.latitude, longitude = excluded.longitude, payload = excluded.payload,
                        payload_version = excluded.payload_version, cached_at = excluded.cached_at,
                        last_accessed_at = excluded.last_accessed_at
                    """,
                    arguments: row)
            }
        }
    }

    /// Bounded cache query for offline Explore. Filtering by radius uses a bounding box in SQL and
    /// exact distance in Swift. Rows that can't be decoded are deleted; returned rows are marked as read.
    func cachedVenues(near origin: GeoPoint?, radiusMeters: Double, category: VenueCategory?, text: String?,
                      notOlderThan oldest: Date, limit: Int = 100, accessedAt now: Date = Date()) async throws -> [CachedVenue] {
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
        let sql = """
            SELECT id, payload, payload_version, cached_at FROM cached_venues
            WHERE \(conditions.joined(separator: " AND ")) LIMIT \(max(1, min(limit, 200)))
            """
        let venues = try await readVenues(sql: sql, arguments: Self.arguments(arguments), accessedAt: now)
        return venues.map { cached in
            var result = cached
            result.venue.distanceMeters = origin.map { cached.venue.coordinate.distance(to: $0) }
            return result
        }
    }

    func cachedVenues(ids: [UUID], accessedAt now: Date = Date()) async throws -> [UUID: CachedVenue] {
        guard !ids.isEmpty else { return [:] }
        let sql = "SELECT id, payload, payload_version, cached_at FROM cached_venues WHERE id IN (\(Self.placeholders(ids.count)))"
        let venues = try await readVenues(sql: sql, arguments: Self.arguments(ids.map(\.uuidString)), accessedAt: now)
        return Dictionary(venues.map { ($0.venue.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Runs a `cached_venues` select, deletes rows with a stale payload and touches `last_accessed_at` of the rest.
    private func readVenues(sql: String, arguments: StatementArguments, accessedAt now: Date) async throws -> [CachedVenue] {
        let (venues, dropped) = try await writer.write { db -> ([CachedVenue], Int) in
            var valid: [CachedVenue] = []
            var invalid: [String] = []
            for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                let id: String = row["id"]
                if let venue = Self.decode(VenueSummary.self, payload: row["payload"], version: row["payload_version"]) {
                    valid.append(CachedVenue(venue: venue, cachedAt: row["cached_at"]))
                } else {
                    invalid.append(id)
                }
            }
            if !invalid.isEmpty {
                try db.execute(sql: "DELETE FROM cached_venues WHERE id IN (\(Self.placeholders(invalid.count)))",
                               arguments: Self.arguments(invalid))
            }
            if !valid.isEmpty {
                let ids = valid.map { $0.venue.id.uuidString as any DatabaseValueConvertible }
                try db.execute(sql: "UPDATE cached_venues SET last_accessed_at = ? WHERE id IN (\(Self.placeholders(ids.count)))",
                               arguments: Self.arguments([now] + ids))
            }
            return (valid, invalid.count)
        }
        if dropped > 0 { Self.logger.notice("Dropped \(dropped) cached venue(s) with an outdated payload") }
        return venues
    }

    // MARK: Venue details

    /// Stores the public part of a detail. Per-user fields are never written.
    func storeVenueDetail(_ detail: VenueDetail, at date: Date) async throws {
        let data = try Self.encoder.encode(VenueDetailPayload(detail))
        try await writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO cached_venue_details (venue_id, payload, payload_version, cached_at, last_accessed_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(venue_id) DO UPDATE SET payload = excluded.payload, payload_version = excluded.payload_version,
                    cached_at = excluded.cached_at, last_accessed_at = excluded.last_accessed_at
                """,
                arguments: [detail.id.uuidString, data, VenueDetailPayload.payloadVersion, date, date])
        }
    }

    /// The cached detail if present, fresh enough and readable. An unreadable row is deleted.
    func cachedVenueDetail(id: UUID, notOlderThan oldest: Date, accessedAt now: Date = Date()) async throws -> CachedVenueDetail? {
        let key = id.uuidString
        let (result, dropped) = try await writer.write { db -> (CachedVenueDetail?, Bool) in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT payload, payload_version, cached_at FROM cached_venue_details WHERE venue_id = ?", arguments: [key])
            else { return (nil, false) }
            guard let payload = Self.decode(VenueDetailPayload.self, payload: row["payload"], version: row["payload_version"]) else {
                try db.execute(sql: "DELETE FROM cached_venue_details WHERE venue_id = ?", arguments: [key])
                return (nil, true)
            }
            let cachedAt: Date = row["cached_at"]
            guard cachedAt >= oldest else { return (nil, false) }
            try db.execute(sql: "UPDATE cached_venue_details SET last_accessed_at = ? WHERE venue_id = ?", arguments: [now, key])
            return (CachedVenueDetail(detail: payload.detail, cachedAt: cachedAt), false)
        }
        if dropped { Self.logger.notice("Dropped a cached venue detail with an outdated payload") }
        return result
    }

    // MARK: Pruning

    nonisolated struct PruneResult: Hashable, Sendable {
        var venues: Int
        var details: Int
    }

    /// Deletes cached rows older than `maxAge`, then keeps at most the given number of rows per table,
    /// evicting the least recently read first. Drafts, favorites, uploads and `app_kv` are untouched.
    @discardableResult
    func prune(now: Date, maxAge: TimeInterval, maxVenues: Int, maxDetails: Int) async throws -> PruneResult {
        let oldest = now.addingTimeInterval(-maxAge)
        return try await writer.write { db in
            try db.execute(sql: "DELETE FROM cached_venues WHERE cached_at < ?", arguments: [oldest])
            var venues = db.changesCount
            try db.execute(sql: """
                DELETE FROM cached_venues WHERE id IN
                    (SELECT id FROM cached_venues ORDER BY last_accessed_at DESC, cached_at DESC LIMIT -1 OFFSET ?)
                """, arguments: [max(0, maxVenues)])
            venues += db.changesCount

            try db.execute(sql: "DELETE FROM cached_venue_details WHERE cached_at < ?", arguments: [oldest])
            var details = db.changesCount
            try db.execute(sql: """
                DELETE FROM cached_venue_details WHERE venue_id IN
                    (SELECT venue_id FROM cached_venue_details ORDER BY last_accessed_at DESC, cached_at DESC LIMIT -1 OFFSET ?)
                """, arguments: [max(0, maxDetails)])
            details += db.changesCount
            return PruneResult(venues: venues, details: details)
        }
    }

    func prune(now: Date = Date(), configuration: AppConfiguration) async throws {
        let result = try await prune(now: now, maxAge: configuration.venueCacheMaxAge,
                                     maxVenues: configuration.venueCacheMaxEntries,
                                     maxDetails: configuration.venueDetailCacheMaxEntries)
        Self.logger.info("Pruned \(result.venues) venue card(s) and \(result.details) detail(s)")
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

    // MARK: Drafts (always scoped to one user)

    func saveDraft<T: LocalPayload>(_ value: T, key: String, userID: UUID, at date: Date = Date()) async throws {
        let data = try Self.encoder.encode(value)
        try await writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO local_drafts (user_id, key, payload, payload_version, updated_at) VALUES (?, ?, ?, ?, ?)
                """, arguments: [userID.uuidString, key, data, T.payloadVersion, date])
        }
    }

    /// The user's draft, or nil. A draft of another payload version (or unreadable) is deleted.
    func draft<T: LocalPayload>(_ type: T.Type, key: String, userID: UUID) async throws -> T? {
        let user = userID.uuidString
        let (value, dropped) = try await writer.write { db -> (T?, Bool) in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT payload, payload_version FROM local_drafts WHERE user_id = ? AND key = ?", arguments: [user, key])
            else { return (nil, false) }
            if let value = Self.decode(T.self, payload: row["payload"], version: row["payload_version"]) { return (value, false) }
            try db.execute(sql: "DELETE FROM local_drafts WHERE user_id = ? AND key = ?", arguments: [user, key])
            return (nil, true)
        }
        if dropped { Self.logger.notice("Dropped a draft with an outdated payload") }
        return value
    }

    func deleteDraft(key: String, userID: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM local_drafts WHERE user_id = ? AND key = ?", arguments: [userID.uuidString, key])
        }
    }

    func deleteDrafts(userID: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM local_drafts WHERE user_id = ?", arguments: [userID.uuidString])
        }
    }

    // MARK: Pending uploads

    func enqueueUpload(_ upload: PendingUpload) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                INSERT INTO pending_uploads (id, user_id, kind, target_id, venue_id, local_path, mime_type, attempts,
                    last_error, next_attempt_at, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [upload.id.uuidString, upload.userID.uuidString, upload.kind.rawValue, upload.targetID.uuidString,
                                 upload.venueID?.uuidString, upload.fileName, upload.mimeType, upload.attempts,
                                 upload.lastError, upload.nextAttemptAt, upload.createdAt])
        }
    }

    /// The user's uploads whose `next_attempt_at` has passed, oldest first.
    func dueUploads(userID: UUID, now: Date, limit: Int = 20) async throws -> [PendingUpload] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM pending_uploads WHERE user_id = ? AND next_attempt_at <= ?
                ORDER BY next_attempt_at, created_at LIMIT ?
                """, arguments: [userID.uuidString, now, max(1, limit)])
                .compactMap(Self.pendingUpload)
        }
    }

    func pendingUploads(userID: UUID) async throws -> [PendingUpload] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM pending_uploads WHERE user_id = ? ORDER BY created_at",
                             arguments: [userID.uuidString])
                .compactMap(Self.pendingUpload)
        }
    }

    /// Records a failed attempt and schedules the next one.
    func markUploadAttempt(id: UUID, error: String, nextAttemptAt: Date) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE pending_uploads SET attempts = attempts + 1, last_error = ?, next_attempt_at = ? WHERE id = ?",
                           arguments: [error, nextAttemptAt, id.uuidString])
        }
    }

    func removeUpload(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM pending_uploads WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// File names referenced by any user's queued upload.
    func allPendingUploadFileNames() async throws -> Set<String> {
        try await Set(writer.read { db in try String.fetchAll(db, sql: "SELECT local_path FROM pending_uploads") })
    }

    private static func pendingUpload(_ row: Row) -> PendingUpload? {
        guard let id = UUID(uuidString: row["id"]), let userID = UUID(uuidString: row["user_id"]),
              let kind = PendingUploadKind(rawValue: row["kind"]), let targetID = UUID(uuidString: row["target_id"])
        else { return nil }
        return PendingUpload(id: id, userID: userID, kind: kind, targetID: targetID,
                             venueID: (row["venue_id"] as String?).flatMap(UUID.init(uuidString:)),
                             fileName: row["local_path"], mimeType: row["mime_type"], attempts: row["attempts"],
                             lastError: row["last_error"], nextAttemptAt: row["next_attempt_at"], createdAt: row["created_at"])
    }

    // MARK: Per-user data

    /// Deletes everything private to `userID` (drafts, cached favorites, pending uploads) in one transaction.
    /// Returns the file names of the removed uploads so the caller can delete the files.
    @discardableResult
    func removeUserData(userID: UUID) async throws -> [String] {
        let user = userID.uuidString
        return try await writer.write { db in
            let files = try String.fetchAll(db, sql: "SELECT local_path FROM pending_uploads WHERE user_id = ?", arguments: [user])
            try db.execute(sql: "DELETE FROM local_drafts WHERE user_id = ?", arguments: [user])
            try db.execute(sql: "DELETE FROM cached_favorites WHERE user_id = ?", arguments: [user])
            try db.execute(sql: "DELETE FROM pending_uploads WHERE user_id = ?", arguments: [user])
            return files
        }
    }

    // MARK: App key-value (device state)

    func value<T: Decodable & Sendable>(_ type: T.Type, forKey key: String) throws -> T? {
        let data = try writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM app_kv WHERE key = ?", arguments: [key])
        }
        guard let data else { return nil }
        if let value = try? Self.decoder.decode(T.self, from: data) { return value }
        try writer.write { db in try db.execute(sql: "DELETE FROM app_kv WHERE key = ?", arguments: [key]) }
        Self.logger.notice("Dropped unreadable app_kv value for \(key, privacy: .public)")
        return nil
    }

    func setValue<T: Encodable & Sendable>(_ value: T, forKey key: String, at date: Date = Date()) async throws {
        let data = try Self.encoder.encode(value)
        try await writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO app_kv (key, value, updated_at) VALUES (?, ?, ?)", arguments: [key, data, date])
        }
    }

    // MARK: Remote config

    static let remoteConfigKey = V3ProductionHardening.remoteConfigKey

    /// Synchronous on purpose: read once at launch, before the first screen, so it already uses server limits.
    func cachedRemoteConfig() -> RemoteConfigValues? {
        try? value(RemoteConfigValues.self, forKey: Self.remoteConfigKey)
    }

    func storeRemoteConfig(_ values: RemoteConfigValues) async throws {
        try await setValue(values, forKey: Self.remoteConfigKey)
    }

    // MARK: Maintenance

    /// "Clear cache": removes cached content and drafts. Device state (`app_kv`) and the photo outbox
    /// (`pending_uploads`: photos of already-published content) are kept.
    func clearAll() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM cached_venues")
            try db.execute(sql: "DELETE FROM cached_venue_details")
            try db.execute(sql: "DELETE FROM cached_favorites")
            try db.execute(sql: "DELETE FROM local_drafts")
        }
    }

    func cachedVenueCount() async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_venues") ?? 0 }
    }
}
