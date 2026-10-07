import Foundation

enum TempFileJanitor {
    private static let stagingFolders = ["DownloadCache", "incoming_imports", "music_import_staging"]
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    static func sweepStaleFiles() {
        let referenced = QueuePersistenceStore.referencedLocalPaths().map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let folders = stagingFolders
        let cutoff = Date().addingTimeInterval(-maxAge)
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var removed = 0
            for folder in folders {
                let root = fm.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
                guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
                for case let url as URL in enumerator {
                    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                          values.isRegularFile == true,
                          let modified = values.contentModificationDate,
                          modified < cutoff,
                          !referenced.contains(url.standardizedFileURL.path) else { continue }
                    if (try? fm.removeItem(at: url)) != nil { removed += 1 }
                }
            }
            if removed > 0 {
                Logger.shared.log("[TempFileJanitor] Removed \(removed) stale temp file(s)")
            }
        }
    }
}
