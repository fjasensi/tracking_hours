import Foundation

final class AutomaticBackupService {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let bookmarkKey = "automaticBackupParentBookmark"
    private let backupDirectoryName = "Tracking Hours Backups"
    private let maximumBackupCount = 30

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    var directoryURL: URL? {
        guard let parentURL = try? resolvedParentURL() else {
            return nil
        }

        return parentURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    func configure(parentURL: URL) throws -> URL {
        let hasAccess = parentURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                parentURL.stopAccessingSecurityScopedResource()
            }
        }

        let backupURL = parentURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        let bookmark = try parentURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)
        return backupURL
    }

    func disable() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    @discardableResult
    func createBackup(from data: Data, reason: String = "backup") throws -> URL? {
        guard let parentURL = try resolvedParentURL() else {
            return nil
        }

        guard parentURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(
                .fileReadNoPermission,
                userInfo: [NSLocalizedDescriptionKey: "Jira Hours no longer has access to the backup folder. Choose it again in Settings."]
            )
        }
        defer { parentURL.stopAccessingSecurityScopedResource() }

        let backupURL = parentURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let timestamp = formatter.string(from: Date())
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let fileURL = backupURL.appendingPathComponent("tracking-hours-\(reason)-\(timestamp)-\(suffix).json")
        try data.write(to: fileURL, options: [.atomic])
        try removeOldBackups(in: backupURL)
        return fileURL
    }

    private func resolvedParentURL() throws -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            let refreshedBookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(refreshedBookmark, forKey: bookmarkKey)
        }

        return url
    }

    private func removeOldBackups(in directoryURL: URL) throws {
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.hasPrefix("tracking-hours-") }

        let sortedFiles = files.sorted {
            let firstDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let secondDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return firstDate > secondDate
        }

        for fileURL in sortedFiles.dropFirst(maximumBackupCount) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
