import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library
extension SettingsView {
    var repairSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIBRARY TOOLS")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                NavigationLink {
                    LibraryRepairView(manager: manager, status: $status)
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Library Tools")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Repair your library and turn on features like Favorites")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }

    var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOWNLOADS")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                NavigationLink {
                    DownloaderSettingsScreen(
                        metadataSource: $metadataSource,
                        autofetchMetadata: $autofetchMetadata,
                        keepLocalMetadataForLocalFiles: $keepLocalMetadataForLocalFiles,
                        fetchLyrics: $fetchLyrics,
                        appleSubscriptionLyrics: $appleSubscriptionLyrics,
                        storeRegion: $storeRegion,
                        appleRichMetadata: $appleRichMetadata,
                        downloadSearchProvider: $downloadSearchProvider,
                        keepDownloadedSongs: $keepDownloadedSongs,
                        tagKeptDownloadedSongs: $tagKeptDownloadedSongs,
                        backgroundDownloadsEnabled: $backgroundDownloadsEnabled,
                        showingDownloadFolderPicker: $showingDownloadFolderPicker,
                        yoinkifyFormat: $yoinkifyFormat,
                        downloadFolderSubtitle: downloadFolderSubtitle
                    )
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Metadata & Download Settings")
                                .font(.body)
                            Text("Metadata source, downloader, quality, and saved downloads")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }

    var deviceLibrarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEVICE LIBRARY")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                NavigationLink {
                    DeviceLibraryBrowserView(manager: manager)
                } label: {
                    HStack {
                        Image(systemName: "music.note.list")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-Device Library")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Edit, delete, and export songs already on the phone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .disabled(!manager.heartbeatReady)
                .opacity(manager.heartbeatReady ? 1 : 0.55)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )

        }
    }

    var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BACKUP & RESTORE")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                NavigationLink {
                    BackupRestoreView(manager: manager)
                } label: {
                    HStack {
                        Image(systemName: "archivebox.fill")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backup & Restore")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Back up database/snapshots or backup & restore playlists")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }
}
