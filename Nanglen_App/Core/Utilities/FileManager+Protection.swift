import Foundation

nonisolated extension FileManager {
    /// Creates `url` if needed and gives it — and every file already inside it — the
    /// `.completeUntilFirstUserAuthentication` data-protection class. New files created inside inherit it.
    ///
    /// That class keeps the files encrypted until the device is first unlocked after boot, while still
    /// letting background work (photo retries, launch in the background) read them afterwards.
    func createProtectedDirectory(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try setAttributes(protection, ofItemAtPath: url.path)
        for name in (try? contentsOfDirectory(atPath: url.path)) ?? [] {
            try? setAttributes(protection, ofItemAtPath: url.appendingPathComponent(name).path)
        }
    }
}
