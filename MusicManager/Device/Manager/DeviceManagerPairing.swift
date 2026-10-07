import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Pairing
extension DeviceManager {
    func refreshExpectedPairingFileState() {
        hasValidExpectedPairingFile = validateExpectedPairingFile()
    }

    func importPairingFile(from url: URL) throws {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let directory = expectedPairingFile.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.copyItem(at: url, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let matchesExpectedFormat = requiresRPPairingTunnel
            ? validateRPPairingFile(at: tempURL)
            : validateLockdownPairingFile(at: tempURL)

        guard matchesExpectedFormat else {
            let matchesOtherFormat = requiresRPPairingTunnel
                ? validateLockdownPairingFile(at: tempURL)
                : validateRPPairingFile(at: tempURL)

            if matchesOtherFormat {
                let otherTitle = requiresRPPairingTunnel ? "classic Pairing File" : "RP Pairing File"
                throw PairingFileImportError.wrongFormatForOSVersion(expected: expectedPairingFileTitle, detectedOther: otherTitle)
            }
            throw PairingFileImportError.invalidFileType(expected: expectedPairingFileTitle)
        }

        if FileManager.default.fileExists(atPath: expectedPairingFile.path) {
            _ = try FileManager.default.replaceItemAt(expectedPairingFile, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: expectedPairingFile)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: expectedPairingFile.path)

        refreshExpectedPairingFileState()
    }

    func validateExpectedPairingFile() -> Bool {
        let file = expectedPairingFile
        guard FileManager.default.fileExists(atPath: file.path) else {
            return false
        }

        if requiresRPPairingTunnel {
            return validateRPPairingFile(at: file)
        }

        return validateLockdownPairingFile(at: file)
    }

    func validateLockdownPairingFile(at file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return false
        }

        var pairingPtr: IdevicePairingFile?
        let readErr = idevice_pairing_file_read(file.path, &pairingPtr)
        guard readErr == IdeviceSuccess, let pairingHandle = pairingPtr else {
            return false
        }
        idevice_pairing_file_free(pairingHandle)
        return true
    }

    func validateRPPairingFile(at file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return false
        }

        var rpPairingPtr: RpPairingFileHandle?
        let readErr = rp_pairing_file_read(file.path, &rpPairingPtr)
        guard readErr == IdeviceSuccess, let rpPairingHandle = rpPairingPtr else {
            return false
        }
        rp_pairing_file_free(rpPairingHandle)
        return true
    }
}
