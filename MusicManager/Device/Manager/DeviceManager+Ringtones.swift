import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

extension DeviceManager {
    func injectRingtones(ringtones: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectRingtones called with \(ringtones.count) ringtones")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let dbVersion = self.getDatabaseVersion()
            let requiresRingtoneDBEntries = dbVersion.major <= 18
            let primaryRoot = "/iTunes_Control/Ringtones"
            let legacyRoot = "/iTunes_Control/Ringtons"
            var resolvedRoot = primaryRoot
            
            
            progress("Preparing ringtones...")
            Logger.shared.log("[DeviceManager] Downloading existing Ringtones.plist")

            var rootDict: [String: Any] = [:]
            var ringtonesDict: [String: Any] = [:]

            let plistSem = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "\(primaryRoot)/Ringtones.plist") { data in
                if let data = data {
                    if let dict = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                        rootDict = dict
                        ringtonesDict = (dict["Ringtones"] as? [String: Any]) ?? [:]
                        resolvedRoot = primaryRoot
                        Logger.shared.log("[DeviceManager] Loaded existing plist with \(ringtonesDict.count) entries")
                    }
                } else {
                    let legacySem = DispatchSemaphore(value: 0)
                    self.downloadFileFromDevice(remotePath: "\(legacyRoot)/Ringtones.plist") { legacyData in
                        if let legacyData = legacyData,
                           let dict = try? PropertyListSerialization.propertyList(from: legacyData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                            rootDict = dict
                            ringtonesDict = (dict["Ringtones"] as? [String: Any]) ?? [:]
                            resolvedRoot = legacyRoot
                            Logger.shared.log("[DeviceManager] Loaded existing legacy plist with \(ringtonesDict.count) entries")
                        }
                        legacySem.signal()
                    }
                    legacySem.waitForTransfer()
                }
                plistSem.signal()
            }
            plistSem.waitForTransfer()

            var afcDir: AfcClientHandle?
            self.connectAfcClient(&afcDir)
            if afcDir != nil {
                afc_make_directory(afcDir, primaryRoot)
                afc_make_directory(afcDir, "\(primaryRoot)/Sync")
                afc_make_directory(afcDir, legacyRoot)
                afc_make_directory(afcDir, "\(legacyRoot)/Sync")
                afc_client_free(afcDir)
            }

            progress("Uploading ringtones...")
            var uploadedRingtones: [SongMetadata] = []

            for ringtone in ringtones {
                let remotePath = "\(resolvedRoot)/\(ringtone.remoteFilename)"
                let mirrorPath = "\(resolvedRoot == primaryRoot ? legacyRoot : primaryRoot)/\(ringtone.remoteFilename)"

                let uploadSem = DispatchSemaphore(value: 0)
                var uploadOK = false
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: remotePath) { s in
                    uploadOK = s
                    uploadSem.signal()
                }
                uploadSem.waitForTransfer()
                
                let mirrorSem = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: mirrorPath) { _ in
                    mirrorSem.signal()
                }
                mirrorSem.waitForTransfer()

                if uploadOK {
                    Logger.shared.log("[DeviceManager] Uploaded: \(ringtone.remoteFilename)")
                    uploadedRingtones.append(ringtone)
                } else {
                    Logger.shared.log("[DeviceManager] WARNING: Failed to upload \(ringtone.remoteFilename)")
                    continue
                }

                let pid  = SongMetadata.generatePersistentId()
                let guid = String(format: "%016llX", SongMetadata.generatePersistentId())

                let entry: [String: Any] = [
                    "Name":              ringtone.title,
                    "Total Time":        ringtone.durationMs,
                    "PID":               pid,
                    "Protected Content": false,
                    "GUID":              guid
                ]
                ringtonesDict[ringtone.remoteFilename] = entry
                Logger.shared.log("[DeviceManager] Plist entry: \(ringtone.remoteFilename) PID=\(pid) GUID=\(guid)")
            }

            rootDict["Ringtones"] = ringtonesDict

            do {
                let tempDir  = FileManager.default.temporaryDirectory
                let plistData = try PropertyListSerialization.data(fromPropertyList: rootDict, format: .binary, options: 0)
                let tempPlist = tempDir.appendingPathComponent("Ringtones.plist")
                try plistData.write(to: tempPlist)

                let plistSem2 = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: tempPlist, remotePath: "\(resolvedRoot)/Ringtones.plist") { _ in
                    plistSem2.signal()
                }
                plistSem2.waitForTransfer()
                
                let plistSemMirror = DispatchSemaphore(value: 0)
                let mirrorPlistRoot = (resolvedRoot == primaryRoot) ? legacyRoot : primaryRoot
                self.uploadFileToDevice(localURL: tempPlist, remotePath: "\(mirrorPlistRoot)/Ringtones.plist") { _ in
                    plistSemMirror.signal()
                }
                plistSemMirror.waitForTransfer()
                Logger.shared.log("[DeviceManager] Ringtones.plist uploaded (\(ringtonesDict.count) total entries)")
            } catch {
                Logger.shared.log("[DeviceManager] Failed to upload Ringtones.plist: \(error)")
            }
            
            do {
                let anchor: [String: Any] = ["syncAnchor": "1"]
                let anchorData = try PropertyListSerialization.data(fromPropertyList: anchor, format: .binary, options: 0)
                let anchorURL = FileManager.default.temporaryDirectory.appendingPathComponent("SyncAnchor.plist")
                try anchorData.write(to: anchorURL)
                
                let anchorSem1 = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: anchorURL, remotePath: "\(resolvedRoot)/SyncAnchor.plist") { _ in
                    anchorSem1.signal()
                }
                anchorSem1.waitForTransfer()
                
                let anchorSem2 = DispatchSemaphore(value: 0)
                let mirrorAnchorRoot = (resolvedRoot == primaryRoot) ? legacyRoot : primaryRoot
                self.uploadFileToDevice(localURL: anchorURL, remotePath: "\(mirrorAnchorRoot)/SyncAnchor.plist") { _ in
                    anchorSem2.signal()
                }
                anchorSem2.waitForTransfer()
                Logger.shared.log("[Ringtone-DB] SyncAnchor.plist uploaded")
            } catch {
                Logger.shared.log("[Ringtone-DB] Failed to upload SyncAnchor.plist: \(error)")
            }
            
            if requiresRingtoneDBEntries && !uploadedRingtones.isEmpty {
                progress("Updating ringtone database...")
                Logger.shared.log("[Ringtone-DB] iOS \(dbVersion.major) detected: inserting DB rows for \(uploadedRingtones.count) ringtone(s)")
                
                var dbData: Data?
                var walData: Data?
                var shmData: Data?
                
                let dbSem = DispatchSemaphore(value: 0)
                self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                    dbData = data
                    dbSem.signal()
                }
                dbSem.waitForTransfer()
                
                guard let baseDbData = dbData else {
                    Logger.shared.log("[Ringtone-DB] Failed to download MediaLibrary.sqlitedb, skipping DB insertion")
                    progress("Done!")
                    self.postRingtoneRefreshNotifications()
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                
                let walSem = DispatchSemaphore(value: 0)
                self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                    walData = data
                    walSem.signal()
                }
                walSem.waitForTransfer()
                
                let shmSem = DispatchSemaphore(value: 0)
                self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                    shmData = data
                    shmSem.signal()
                }
                shmSem.waitForTransfer()
                
                do {
                    let updatedDbURL = try MediaLibraryBuilder.addRingtonesToExistingDatabase(
                        existingDbData: baseDbData,
                        walData: walData,
                        shmData: shmData,
                        ringtones: uploadedRingtones
                    )
                    
                    let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
                    let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
                    let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
                    let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
                    
                    let uploadSem = DispatchSemaphore(value: 0)
                    var uploadOK = false
                    self.uploadFileToDevice(localURL: updatedDbURL, remotePath: tempDBPath) { ok in
                        uploadOK = ok
                        uploadSem.signal()
                    }
                    uploadSem.waitForTransfer()
                    
                    if uploadOK {
                        var afcSwap: AfcClientHandle?
                        self.connectAfcClient(&afcSwap)
                        if let afcSwap {
                            if self.replaceRemoteMediaLibrary(
                                tempDBPath: tempDBPath,
                                finalDBPath: finalDBPath,
                                shmPath: shmPath,
                                walPath: walPath,
                                afc: afcSwap,
                                logContext: "[Ringtone-DB]"
                            ) {
                                Logger.shared.log("[Ringtone-DB] Database swapped successfully with ringtone entries")
                            } else {
                                Logger.shared.log("[Ringtone-DB] Failed to swap database after ringtone insert")
                            }
                            afc_client_free(afcSwap)
                        } else {
                            Logger.shared.log("[Ringtone-DB] Could not open AFC for database swap")
                        }
                    } else {
                        Logger.shared.log("[Ringtone-DB] Failed to upload updated ringtone database")
                    }
                } catch {
                    Logger.shared.log("[Ringtone-DB] Failed to build/update ringtone database: \(error)")
                }
            } else {
                Logger.shared.log("[Ringtone-DB] DB insertion not required for iOS \(dbVersion.major)")
            }

            progress("Done!")
            self.postRingtoneRefreshNotifications()
            DispatchQueue.main.async { completion(true) }
        }
    }
}
