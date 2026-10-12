import Foundation
import SwiftUI
import Combine

nonisolated final class Logger: ObservableObject, @unchecked Sendable {
    static let shared = Logger()

    var logs: String = "" {
        willSet { objectWillChange.send() }
    }
    private var dateFormatter: DateFormatter


    private let logQueue = DispatchQueue(label: "com.edualexxis.MusicManager.logger")
    private let fileLock = NSLock()
    private var fileHandle: FileHandle?
    private var fileBytesWritten = 0
    private static let maxFileBytes = 4_000_000
    private static let maxLogCharacters = 400_000
    private static let urlQueryPattern = try? NSRegularExpression(pattern: #"(https?://[^\s"'<>?#]+)\?[^\s"'<>]*"#)

    private let suppressedSubstrings: [String] = [
        "[AppleMusicAPI] Fetching token via URLSession...",
        "[AppleMusicAPI] Found JS bundle:",
        "[Download] Requesting http",
        "[Download] Received JSON redirect:",
        "[Download] Resolved manifest media URL:",
        "[Download] Matching from Apple metadata",
        "[Download] Matching from iTunes metadata fallback",
        "[Download] Matching from Deezer metadata fallback",
        "[Download] Song.link mapping failed",
        "[Download] Song.link Deezer mapping failed",
        "[Download] Failed to map Apple Music track",
        "[Download] Mapped Apple Music source URL",
        "[Download] Using source URL",
        "[Download] Spotify fallback:",
        "[Download] Mapped track to Deezer",
        "[Download] Requesting \(Config.downloadBackendLabel)",
        "[Download] Album search fell back",
        "[Download] Playlist search is using",
        "[Download] Attempting last-resort Spotify mapping",
        "[Download] Mapped to Spotify for last-resort retry",
        "[Download] Last-resort Spotify mapping failed",
        "[DeviceManager] downloadFileFromDevice called for: /iTunes_Control/iTunes/Artwork/Originals/",
        "[DeviceManager] downloadFileFromDevice called for: /iTunes_Control/iTunes/MediaLibrary.sqlitedb",
        " bytes from /iTunes_Control/iTunes/Artwork/Originals/",
        "[SongMetadata] Extracted artwork:",
        "[SongMetadata] Deep Scan extracted artwork:",
        "[SongMetadata] Extracted Album Artist:",
        "[SongMetadata] Ignored invalid Album Artist:",
        "[SongMetadata] Extracted year:",
        "[SongMetadata] Extracted and cleaned lyrics",
        "[SongMetadata] Extracted Track via Data:",
        "[SongMetadata] Extracted Disc via Data:",
        "[SongMetadata] Applied FLAC Vorbis fallback metadata",
        "[SongMetadata] Parsed filename",
        "[SongMetadata] M4A release date:",
        "[SongMetadata] M4A year from",
        "[SongMetadata] M4A Apple IDs:",
        "[SongMetadata] Local audio traits detected",
        "[SongMetadata] Successfully fetched lyrics from",
        "[SongMetadata] LRCLIB fetch failed:",
        "[SongMetadata] LRCLIB search failed:",
        "[SongMetadata] Musixmatch search returned no suitable lyric match",
        "[SongMetadata] Musixmatch fallback failed:",
        "[SongMetadata] Musixmatch search failed:",
        "[SongMetadata] Musixmatch lyrics resolve failed:",
        "[SongMetadata] NetEase search returned no suitable lyric match",
        "[SongMetadata] NetEase fallback failed:",
        "[SongMetadata] NetEase search failed:",
        "[SongMetadata] NetEase lyrics resolve failed:",
        "[SongMetadata] Found lyrics from",
        "[SongMetadata] Updated artwork with",
        "[SongMetadata] Searching iTunes for:",
        "[SongMetadata] ✓ Validated match:",
        "[SongMetadata] x Rejected match:",
        "[SongMetadata] No valid iTunes match found after filtering.",
        "[SongMetadata] Searching Deezer for:",
        "[SongMetadata] ✓ Deezer match:",
        "[SongMetadata] Enhanced with Deezer details:",
        "[MusicView] Using enrichment concurrency:",
        "[MusicView] Using import chunk size:",
        "[MusicView] Large import detected."
    ]

    private static var logsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }

    static var currentSessionFileURL: URL {
        logsDirectory.appendingPathComponent("Session_Current.log")
    }

    static var previousSessionFileURL: URL {
        logsDirectory.appendingPathComponent("Session_Previous.log")
    }

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        openSessionFile()
        log("===========================================")
        log("Logger Initialized")
        log("===========================================")
    }

    private func openSessionFile() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.logsDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: Self.currentSessionFileURL.path) {
                try? fm.removeItem(at: Self.previousSessionFileURL)
                try fm.moveItem(at: Self.currentSessionFileURL, to: Self.previousSessionFileURL)
            }
            fm.createFile(atPath: Self.currentSessionFileURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: Self.currentSessionFileURL)
        } catch {
            fileHandle = nil
        }
    }

    private func appendToSessionFile(_ line: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let handle = fileHandle, let data = (line + "\n").data(using: .utf8) else { return }
        if fileBytesWritten + data.count > Self.maxFileBytes {
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
            fileBytesWritten = 0
        }
        do {
            try handle.write(contentsOf: data)
            fileBytesWritten += data.count
        } catch {
            fileHandle = nil
        }
    }

    static func previousSessionLog() -> String {
        (try? String(contentsOf: previousSessionFileURL, encoding: .utf8)) ?? ""
    }

    func log(_ message: String) {
        guard shouldLog(message) else { return }
        let timestamp = dateFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] \(Self.redact(message))"
        appendToSessionFile(formattedMessage)

        #if DEBUG
        print(formattedMessage)
        #endif

        logQueue.async {
            DispatchQueue.main.async {
                self.logs.append(formattedMessage + "\n")
                if self.logs.count > Self.maxLogCharacters {
                    let overflow = self.logs.count - Self.maxLogCharacters * 3 / 4
                    self.logs.removeFirst(overflow)
                }
            }
        }
    }

    private static func redact(_ message: String) -> String {
        guard message.contains("?"), let pattern = urlQueryPattern else { return message }
        let range = NSRange(message.startIndex..., in: message)
        return pattern.stringByReplacingMatches(in: message, range: range, withTemplate: "$1?<redacted>")
    }

    private func shouldLog(_ message: String) -> Bool {
        for fragment in suppressedSubstrings where message.contains(fragment) {
            return false
        }
        return true
    }

    func clear() {
        logQueue.async {
            DispatchQueue.main.async {
                self.logs = ""
            }
        }
    }

    func saveLogs() -> URL? {
        let fileManager = FileManager.default
        let logsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        let fileURL = logsDirectory.appendingPathComponent("MusicManager_Logs.txt")

        do {
            if !fileManager.fileExists(atPath: logsDirectory.path) {
                try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            try logs.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
