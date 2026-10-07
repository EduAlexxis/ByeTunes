import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Playlists
extension DeviceManager {
    enum PlaylistAction {
        case create(name: String)
        case createWithSongs(name: String, songPids: [Int64])
        case delete(containerPid: Int64)
        case rename(containerPid: Int64, newName: String)
        case removeSong(containerPid: Int64, itemPid: Int64)
        case reorder(containerPid: Int64, orderedItemPids: [Int64])
        case addSongs(containerPid: Int64, itemPids: [Int64])
        case setCoverArtwork(containerPid: Int64, imageData: Data)
    }

    static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func artworkRelativePath(fromToken token: String) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let tokenData = Data(token.utf8)
        tokenData.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(tokenData.count), &hash)
        }
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        return "\(hashString.prefix(2))/\(hashString.dropFirst(2))"
    }

    func applyPlaylistEdits(actions: [PlaylistAction], completion: @escaping (Bool, String) -> Void) {
        guard let staged = stageCurrentMediaLibraryForMutation(label: "playlist_edit") else {
            completion(false, "Failed to pull database from device.")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: staged.tempDir)
        }

        var db: OpaquePointer?
        var pendingCoverUploads: [(remotePath: String, imageData: Data)] = []
        if sqlite3_open(staged.dbURL.path, &db) == SQLITE_OK {
            do {
                for action in actions {
                    switch action {
                    case .create(let name):
                        try MediaLibraryBuilder.createPlaylist(db: db, playlistName: name, songPids: [])
                    case .createWithSongs(let name, let songPids):
                        try MediaLibraryBuilder.createPlaylist(db: db, playlistName: name, songPids: songPids)
                    case .delete(let pid):
                        try MediaLibraryBuilder.deletePlaylist(db: db, containerPid: pid)
                    case .rename(let pid, let newName):
                        try MediaLibraryBuilder.renamePlaylist(db: db, containerPid: pid, newName: newName)
                    case .removeSong(let containerPid, let itemPid):
                        try MediaLibraryBuilder.removeSongFromPlaylist(db: db, containerPid: containerPid, itemPid: itemPid)
                    case .reorder(let containerPid, let orderedItemPids):
                        try MediaLibraryBuilder.reorderSongsInPlaylist(db: db, containerPid: containerPid, orderedItemPids: orderedItemPids)
                    case .addSongs(let containerPid, let itemPids):
                        try MediaLibraryBuilder.addToPlaylist(db: db, containerPid: containerPid, songPids: itemPids)
                    case .setCoverArtwork(let containerPid, let imageData):
                        let artworkToken = Self.sha256Hex(imageData)
                        let relativePath = Self.artworkRelativePath(fromToken: artworkToken)
                        try MediaLibraryBuilder.setPlaylistCoverArtwork(db: db, containerPid: containerPid, artworkToken: artworkToken, relativePath: relativePath)
                        pendingCoverUploads.append((remotePath: "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)", imageData: imageData))
                    }
                }
                sqlite3_close(db)
            } catch {
                sqlite3_close(db)
                completion(false, "Database modification failed: \(error)")
                return
            }
        } else {
            completion(false, "Failed to open staged database.")
            return
        }

        if !pendingCoverUploads.isEmpty {
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            guard let afc else {
                completion(false, "Could not open AFC session to upload cover artwork.")
                return
            }
            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals", afc: afc)
            var uploadFailed = false
            for upload in pendingCoverUploads {
                if !self.uploadDataToDevice(upload.imageData, remotePath: upload.remotePath, afc: afc, verify: false) {
                    uploadFailed = true
                }
            }
            afc_client_free(afc)
            if uploadFailed {
                completion(false, "Failed to upload cover artwork.")
                return
            }
        }

        let success = commitStagedMediaLibrary(localDbURL: staged.dbURL)
        if success {
            self.stopHeartbeat()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startHeartbeat()
            }
            completion(true, "Playlists updated successfully.")
        } else {
            completion(false, "Failed to push modified database to device.")
        }
    }
}
