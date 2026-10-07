import SwiftUI
import UniformTypeIdentifiers

// MARK: - Help
extension SettingsView {
    var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HELP & SUPPORT")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Ensure you are connected to your Local Tunnel VPN (e.g., StosVPN, LocalDev VPN).")
                        Text("2. If connected after opening the app, press 'Retry' next to the 'Connecting' status.")
                        Text("3. Go to the Music tab.")
                        Text("4. Tap 'Add Songs' to select your audio files.")
                        Text("5. Tap 'Inject to Device' to sync them to your library.")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.blue)
                        Text("How to Use")
                            .foregroundColor(.primary)
                    }
                }
                .padding()

                Divider().padding(.leading)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("• App Stuck on White/Black Screen?")
                        Text("  Restart your iPhone to force a library reload.")
                        Text("• Songs Not Showing Up?")
                        Text("  The songs likely didn't import correctly. Restart this app and try again.")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("App Crashing / No Songs?")
                            .foregroundColor(.primary)
                    }
                }
                .padding()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("• Artwork Disappeared?")
                        Text("  Restart the music app to refresh the cache.")
                        Text("• Song Not Injected?")
                        Text("  To prevent artwork mix-ups, 'Unknown' songs are skipped in batches. Inject them individually to add them.")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "photo.artframe")
                            .foregroundColor(.purple)
                        Text("Artwork / Missing Songs")
                            .foregroundColor(.primary)
                    }
                }
                .padding()

                Divider().padding(.leading)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("• What is Auto-Inject?")
                        Text("  When you share audio files to MusicManager from other apps (like Files), they are automatically injected to your device if connected.")
                        Text("• Supported Music Formats:")
                        Text("  MP3, M4A, FLAC, WAV, AIFF, Opus")
                        Text("• Supported Ringtone Formats:")
                        Text("  M4R only (MP3 ringtones must be added manually inside the app)")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                            .foregroundColor(.green)
                        Text("Auto-Inject")
                            .foregroundColor(.primary)
                    }
                }
                .padding()

            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }

    var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEBUG")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {

                Button {
                    showingLogViewer = true
                } label: {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        Text("Console")
                            .font(.body)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }

                Divider().padding(.leading, 56)

                Button {
                    exportDatabase()
                } label: {
                    HStack {
                        if isExportingDb {
                            ProgressView()
                                .frame(width: 28)
                        } else {
                            Image(systemName: "cylinder.split.1x2")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                        }

                        Text(isExportingDb ? "Exporting…" : "Export Database")
                            .font(.body)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .disabled(isExportingDb || !manager.heartbeatReady)
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
