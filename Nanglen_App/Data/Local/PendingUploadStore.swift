import Foundation
import ImageIO
import os

/// Files + rows of the photo outbox. A photo is written to `Application Support/PendingUploads/<uuid>.<ext>`
/// (protected until first unlock) and a `pending_uploads` row points at it by file name.
nonisolated final class PendingUploadStore: Sendable {
    /// Nil when no directory could be created: nothing is queued and failed photos are reported as failed.
    let directory: URL?
    private let cache: LocalCache
    private static let logger = Logger(subsystem: "Mach.Nanglen-App", category: "PendingUploads")

    init(cache: LocalCache, directory: URL?) {
        self.cache = cache
        self.directory = directory
        if let directory {
            do {
                try FileManager.default.createProtectedDirectory(at: directory)
            } catch {
                Self.logger.error("Cannot prepare pending uploads directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// `Application Support/PendingUploads`.
    static func defaultDirectory() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PendingUploads", isDirectory: true)
    }

    private func url(for fileName: String) -> URL? {
        // File names are generated here (`<uuid>.<ext>`); never follow a path out of the directory.
        guard let directory, !fileName.contains("/"), !fileName.hasPrefix(".") else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Writes the photo to disk and queues it. Returns false when it couldn't be persisted.
    @discardableResult
    func enqueue(_ photo: PhotoUpload, kind: PendingUploadKind, targetID: UUID, venueID: UUID?, userID: UUID, now: Date) async -> Bool {
        let id = UUID()
        let ext = photo.fileExtension.filter { $0.isLetter || $0.isNumber }
        let fileName = "\(id.uuidString.lowercased()).\(ext.isEmpty ? "jpg" : ext)"
        guard let url = url(for: fileName) else { return false }
        do {
            try photo.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try await cache.enqueueUpload(PendingUpload(
                id: id, userID: userID, kind: kind, targetID: targetID, venueID: venueID, fileName: fileName,
                mimeType: photo.mimeType, nextAttemptAt: now, createdAt: now))
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            Self.logger.error("Could not queue photo: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func due(userID: UUID, now: Date) async throws -> [PendingUpload] {
        try await cache.dueUploads(userID: userID, now: now)
    }

    func all(userID: UUID) async throws -> [PendingUpload] {
        try await cache.pendingUploads(userID: userID)
    }

    /// Rebuilds the upload from disk (dimensions are read back from the image), or nil when the file is gone/unreadable.
    func photo(for upload: PendingUpload) -> PhotoUpload? {
        guard let url = url(for: upload.fileName), let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return PhotoUpload(data: data, mimeType: upload.mimeType, fileExtension: url.pathExtension, width: width, height: height)
    }

    func markAttempt(_ upload: PendingUpload, error: String, nextAttemptAt: Date) async throws {
        try await cache.markUploadAttempt(id: upload.id, error: error, nextAttemptAt: nextAttemptAt)
    }

    /// Removes the row and its file (after success, or when giving up).
    func remove(_ upload: PendingUpload) async {
        try? await cache.removeUpload(id: upload.id)
        deleteFiles([upload.fileName])
    }

    func deleteFiles(_ fileNames: [String]) {
        for name in fileNames {
            guard let url = url(for: name) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes files no row points at (e.g. the app was killed between writing a file and queuing it).
    func removeOrphanFiles() async {
        guard let directory, let known = try? await cache.allPendingUploadFileNames() else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        deleteFiles(names.filter { !known.contains($0) })
    }

    func fileExists(_ upload: PendingUpload) -> Bool {
        url(for: upload.fileName).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
}
