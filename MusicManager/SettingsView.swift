import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var manager: DeviceManager
    @Binding var status: String
    
    @State private var showingPairingPicker = false
    @State private var showingDownloadFolderPicker = false
    @State private var showingDeleteAlert = false
    
    @State private var showingLogViewer = false
    @State private var exportedDbURLs: [URL] = []
    @State private var showingDbExportSheet = false
    @State private var isExportingDb = false
    @State private var isSnapshotBusy = false
    @State private var isCreatingSnapshot = false
    @State private var isRestoringSnapshot = false
    @State private var snapshotProgressTitle = "Working on Backup"
    @State private var snapshotProgressMessage = "Preparing..."
    @State private var snapshotProgress: Double? = nil
    @State private var isFixingArtwork = false
    @State private var artworkFixMessage = "Fixing artwork..."
    @State private var artworkFixProgress: Double? = nil
    @State private var snapshots: [DeviceManager.DatabaseSnapshotInfo] = []
    @State private var isCheckingForUpdate = false
    @State private var settingsUpdate: AppUpdateInfo?
    
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    @AppStorage("metadataSource") private var metadataSource = "local"
    @AppStorage("autofetchMetadata") private var autofetchMetadata = true
    @AppStorage("fetchLyrics") private var fetchLyrics = false
    @AppStorage("appleSubscriptionLyrics") private var appleSubscriptionLyrics = false
    @AppStorage("storeRegion") private var storeRegion = "US"
    @AppStorage("appleRichMetadata") private var appleRichMetadata = true
    @AppStorage("keepDownloadedSongs") private var keepDownloadedSongs = false
    @AppStorage("fullBackupSnapshots") private var fullBackupSnapshots = false
    @AppStorage("downloadServer") private var downloadServer = DownloaderServerPreference.auto.rawValue
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 8)
                
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONNECTION")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 0) {
                        
                        Button {
                            showingPairingPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(manager.expectedPairingFileTitle)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(manager.connectionStatus)
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
                        
                        Divider().padding(.leading, 56)
                        
                        
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            
                            Text("Status")
                                .font(.body)
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(manager.heartbeatReady ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(manager.connectionStatus)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    manager.startHeartbeat()
                                } label: {
                                    Text("Refresh")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                                .padding(.leading, 8)
                                .disabled(!manager.hasValidExpectedPairingFile)
                                .opacity(manager.hasValidExpectedPairingFile ? 1 : 0.55)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }
                
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("ABOUT")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 0) {
                        Button {
                            if let settingsUpdate {
                                openURL(settingsUpdate.releaseURL)
                            } else {
                                checkForSettingsUpdate()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Version")
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(settingsUpdate == nil ? "Tap to check for updates" : "Tap to download the latest release")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if isCheckingForUpdate {
                                    ProgressView()
                                } else {
                                    Text(settingsUpdate.map { "Update \($0.version)" } ?? AppUpdateChecker.currentVersion)
                                        .font(.subheadline)
                                        .foregroundColor(settingsUpdate == nil ? .secondary : .accentColor)
                                }
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .disabled(isCheckingForUpdate)
                        
                        Divider().padding(.leading, 56)
                        
                        HStack {
                            Image(systemName: "music.note")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            
                            Text("Music Formats")
                                .font(.body)
                            
                            Spacer()
                            
                            Text("MP3, FLAC, M4A, WAV")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
                        Divider().padding(.leading, 56)
                        
                        HStack {
                            Image(systemName: "bell.badge")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            
                            Text("Ringtone Formats")
                                .font(.body)
                            
                            Spacer()
                            
                            Text("M4R, MP3 (Ringtones injection disabled for now")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }
                
                
                
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("METADATA")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            
                            Text("Metadata Source")
                                .font(.body)
                            
                            Spacer()
                            
                            Picker("Metadata Source", selection: $metadataSource) {
                                Text("Local Files").tag("local")
                                Text("iTunes API").tag("itunes")
                                Text("Deezer API").tag("deezer")
                                Text("Apple Music").tag("apple")
                                Text("YouTube").tag("youtube")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
                        if metadataSource != "apple" {
                            Divider().padding(.leading, 56)
                            
                            Toggle(isOn: $appleRichMetadata) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .font(.body)
                                        .foregroundColor(.orange)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Rich Apple Metadata")
                                            .font(.body)
                                        Text("Fetch Store IDs, XID, and Copyright info")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                        }
                        
                        if metadataSource == "itunes" || metadataSource == "deezer" || metadataSource == "apple" || metadataSource == "youtube" {
                            Divider().padding(.leading, 56)
                            
                            Toggle(isOn: $autofetchMetadata) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Autofetch")
                                            .font(.body)
                                        Text("Automatically fetch metadata on import")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                        }
                        
                        if !appleSubscriptionLyrics {
                            Divider().padding(.leading, 56)
                            
                            Toggle(isOn: $fetchLyrics) {
                                HStack {
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Fetch Lyrics")
                                            .font(.body)
                                        Text("Automatically fetch lyrics from LRCLIB, then Musixmatch, then NetEase")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                        }

                        Divider().padding(.leading, 56)

                        Toggle(isOn: $appleSubscriptionLyrics) {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apple Music Subscription Lyrics")
                                        .font(.body)
                                    Text("Use synced Apple Music lyrics for subscribers (internet required).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        
                        if metadataSource == "itunes" {
                                Divider().padding(.leading, 56)
                                
                                HStack {
                                    Image(systemName: "globe")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 28)
                                    
                                    Text("Store Region")
                                        .font(.body)
                                    
                                    Spacer()
                                    
                                    Picker("Region", selection: $storeRegion) {
                                        Text("🇺🇸 US").tag("US")
                                        Text("🇲🇽 MX").tag("MX")
                                        Text("🇪🇸 ES").tag("ES")
                                        Text("🇬🇧 GB").tag("GB")
                                        Text("JP JP").tag("JP")
                                        Text("🇧🇷 BR").tag("BR")
                                        Text("🇩🇪 DE").tag("DE")
                                        Text("🇫🇷 FR").tag("FR")
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                                .padding(.vertical, 10)
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
                
                if manager.supportsIOS26ArtworkRepair {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IOS 26.4+")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            Button {
                                fixArtwork()
                            } label: {
                                HStack {
                                    if isFixingArtwork {
                                        ProgressView()
                                            .frame(width: 28)
                                    } else {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isFixingArtwork ? "Fixing Artwork..." : "Fix Artwork")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Fix artwork and colors for songs added before iOS 26.4. Internet required.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if !isFixingArtwork {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(Color(.systemGray3))
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                            }
                            .disabled(isFixingArtwork || !manager.hasValidExpectedPairingFile)
                            .opacity((isFixingArtwork || manager.hasValidExpectedPairingFile) ? 1 : 0.55)
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }

                
                VStack(alignment: .leading, spacing: 12) {
                    Text("DOWNLOADS")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "server.rack")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Downloader Server")
                                    .font(.body)
                                Text("Choose the backend used for song downloads")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker("Downloader Server", selection: $downloadServer) {
                                ForEach(DownloaderServerPreference.allCases) { server in
                                    Text(server.displayName).tag(server.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)

                        Divider().padding(.leading, 56)

                        Toggle(isOn: $keepDownloadedSongs) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.on.square")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Keep Downloaded Songs")
                                        .font(.body)
                                    Text("Store downloaded tracks in app Documents folder")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)

                        if keepDownloadedSongs {
                            Divider().padding(.leading, 56)

                            Button {
                                showingDownloadFolderPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Download Folder")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(downloadFolderSubtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
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
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("SHORTCUTS")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 0) {
                        Link(destination: URL(string: "https://www.icloud.com/shortcuts/49de36f87bf44b21a38056d3c33e41fe")!) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .font(.body)
                                    .foregroundColor(.purple)
                                    .frame(width: 28)
                                
                                Text("Add ByeTunes Shortcut")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.right")
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
                                Text("  MP3, M4A, FLAC, WAV, AIFF")
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
                
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("CREDITS")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            
                            Link("EduAlexxis", destination: URL(string: "https://github.com/EduAlexxis")!)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
                        Divider().padding(.leading, 56)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.indigo)
                                .frame(width: 28)
                            
                            Link("stossy11", destination: URL(string: "https://github.com/stossy11")!)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
                        Divider().padding(.leading, 56)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "paintbrush.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.orange)
                                .frame(width: 28)
                            
                            Text("u/Zephyrax_g14")
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
                        Divider().padding(.leading, 56)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .frame(width: 28)
                            
                            Link("jkcoxson", destination: URL(string: "https://github.com/jkcoxson/idevice")!)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }
                
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("BACKUP & RESTORE")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 0) {
                        Toggle(isOn: $fullBackupSnapshots) {
                            HStack {
                                Image(systemName: "archivebox.fill")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Full Backup")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text("Back up the database and song files locally. This can take time and use a lot of space.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)

                        Divider().padding(.leading, 56)

                        Button {
                            createSnapshotBackup()
                        } label: {
                            HStack {
                                if isCreatingSnapshot {
                                    ProgressView()
                                        .frame(width: 28)
                                } else {
                                    Image(systemName: "externaldrive.badge.plus")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 28)
                                }
                                
                                Text(isCreatingSnapshot ? "Working…" : "Create Snapshot/Backup")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                        }
                        .disabled(isSnapshotBusy || !manager.heartbeatReady)
                        
                        Divider().padding(.leading, 56)
                        
                        Button {
                            restoreSnapshotBackup()
                        } label: {
                            HStack {
                                if isRestoringSnapshot {
                                    ProgressView()
                                        .frame(width: 28)
                                } else {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 28)
                                }
                                
                                Text(isRestoringSnapshot ? "Working…" : "Restore Snapshot/Backup")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                        }
                        .disabled(isSnapshotBusy || !manager.heartbeatReady)
                        
                        Divider().padding(.leading, 56)
                        
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last Backup")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                if let latest = snapshots.first {
                                    Text("\(latest.songCount) songs • \(formatSnapshotDate(latest.createdAt))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No backup yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                    
                    Text(fullBackupSnapshots ? "Full backup stores a local copy of the database and media files. It can take time and use a lot of space." : "Database-only backup uses less space, but it cannot restore song files deleted by an external sync.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                }
                
                
                // ── DEBUG ──────────────────────────────────────────────────
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("DANGER ZONE")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .font(.body)
                                .foregroundColor(.red)
                                .frame(width: 28)
                            
                            Text("Delete Music Library")
                                .font(.body)
                                .foregroundColor(.red)
                            
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }
                

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showingPairingPicker) {
            DocumentPicker(types: [.data, .xml, .propertyList, .item]) { url in
                handlePairingImport(url: url)
            }
        }
        .sheet(isPresented: $showingDownloadFolderPicker) {
            DocumentPicker(types: [.folder], asCopy: false) { url in
                handleDownloadFolderSelection(url: url)
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
        .sheet(isPresented: $showingDbExportSheet) {
            LogShareSheet(activityItems: exportedDbURLs)
        }
        .alert("Delete Library?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                manager.deleteMediaLibrary { success in
                    DispatchQueue.main.async {
                        if success {
                            self.showToastMessage(title: "Library Deleted", icon: "trash.circle.fill")
                        } else {
                            self.showToastMessage(title: "Deletion Failed", icon: "exclamationmark.triangle.fill")
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently delete your Music library database and playlists from the device. This action cannot be undone.")
        }
        .onAppear {
            refreshSnapshots()
        }

        if isFixingArtwork {
            artworkFixPopup
                .zIndex(90)
        }

        if isSnapshotBusy && (isCreatingSnapshot || isRestoringSnapshot) {
            snapshotProgressPopup
                .zIndex(95)
        }
            
        if showToast {
            HStack(spacing: 12) {
                Image(systemName: toastIcon)
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                
                Text(toastTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 24)
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
        } // ZStack
    } // body

    private var artworkFixPopup: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 6) {
                    Text("Fixing Artwork")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Hang tight, this could take some time.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    if let artworkFixProgress {
                        ProgressView(value: artworkFixProgress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                    }

                    Text(artworkFixMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var snapshotProgressPopup: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: isRestoringSnapshot ? "arrow.counterclockwise.circle.fill" : "externaldrive.badge.plus")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 6) {
                    Text(snapshotProgressTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(isCreatingSnapshot && fullBackupSnapshots ? "Hang tight, full backups can take some time." : "Hang tight, this could take some time.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    if let snapshotProgress {
                        ProgressView(value: snapshotProgress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                    }

                    Text(snapshotProgressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func exportDatabase() {
        isExportingDb = true

        let tmp = FileManager.default.temporaryDirectory
        let files: [(remote: String, local: URL)] = [
            ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb",
             tmp.appendingPathComponent("MediaLibrary.sqlitedb")),
            ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm",
             tmp.appendingPathComponent("MediaLibrary.sqlitedb-shm")),
            ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal",
             tmp.appendingPathComponent("MediaLibrary.sqlitedb-wal")),
            ("/iTunes_Control/Ringtones/Ringtones.plist",
             tmp.appendingPathComponent("Ringtones.plist"))
        ]

        var downloaded: [URL] = []

        func downloadNext(_ index: Int) {
            guard index < files.count else {
                DispatchQueue.main.async {
                    self.isExportingDb = false
                    if downloaded.isEmpty {
                        self.showToastMessage(title: "Export Failed", icon: "xmark.circle.fill")
                    } else {
                        self.exportedDbURLs = downloaded
                        self.showingDbExportSheet = true
                    }
                }
                return
            }

            let file = files[index]
            manager.downloadFileFromDevice(remotePath: file.remote, localURL: file.local) { success in
                if success {
                    downloaded.append(file.local)
                }
                downloadNext(index + 1)
            }
        }

        downloadNext(0)
    }
    
    private func createSnapshotBackup() {
        isSnapshotBusy = true
        isCreatingSnapshot = true
        isRestoringSnapshot = false
        updateSnapshotProgress(title: fullBackupSnapshots ? "Creating Full Backup" : "Creating Backup", message: "Preparing backup...", progress: nil)
        manager.createDatabaseSnapshot { message, progress in
            DispatchQueue.main.async {
                self.updateSnapshotProgress(title: self.fullBackupSnapshots ? "Creating Full Backup" : "Creating Backup", message: message, progress: progress)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.isCreatingSnapshot = false
                self.updateSnapshotProgress(title: self.fullBackupSnapshots ? "Creating Full Backup" : "Creating Backup", message: message, progress: success ? 1 : nil)
                self.showToastMessage(
                    title: success ? message : "Backup Failed: \(message)",
                    icon: success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                self.refreshSnapshots()
            }
        }
    }
    
    private func restoreSnapshotBackup() {
        isSnapshotBusy = true
        isCreatingSnapshot = false
        isRestoringSnapshot = true
        updateSnapshotProgress(title: "Restoring Backup", message: "Preparing restore...", progress: nil)
        manager.restoreLatestDatabaseSnapshot { message, progress in
            DispatchQueue.main.async {
                self.updateSnapshotProgress(title: "Restoring Backup", message: message, progress: progress)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.isRestoringSnapshot = false
                self.updateSnapshotProgress(title: "Restoring Backup", message: message, progress: success ? 1 : nil)
                self.showToastMessage(
                    title: success ? message : "Restore Failed: \(message)",
                    icon: success ? "arrow.counterclockwise.circle.fill" : "xmark.circle.fill"
                )
                self.refreshSnapshots()
            }
        }
    }
    
    private func restoreSnapshot(named folderName: String) {
        isSnapshotBusy = true
        isCreatingSnapshot = false
        isRestoringSnapshot = true
        updateSnapshotProgress(title: "Restoring Backup", message: "Preparing restore...", progress: nil)
        manager.restoreDatabaseSnapshot(named: folderName) { message, progress in
            DispatchQueue.main.async {
                self.updateSnapshotProgress(title: "Restoring Backup", message: message, progress: progress)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.isRestoringSnapshot = false
                self.updateSnapshotProgress(title: "Restoring Backup", message: message, progress: success ? 1 : nil)
                self.showToastMessage(
                    title: success ? message : "Restore Failed: \(message)",
                    icon: success ? "arrow.counterclockwise.circle.fill" : "xmark.circle.fill"
                )
            }
        }
    }

    private func updateSnapshotProgress(title: String, message: String, progress: Double?) {
        snapshotProgressTitle = title
        snapshotProgressMessage = message.isEmpty ? "Working..." : message
        snapshotProgress = progress.map { min(max($0, 0), 1) }
        status = snapshotProgressMessage
    }
    
    private func deleteSnapshot(named folderName: String) {
        isSnapshotBusy = true
        isCreatingSnapshot = false
        isRestoringSnapshot = false
        manager.deleteDatabaseSnapshot(named: folderName) { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.showToastMessage(
                    title: success ? message : "Delete Failed: \(message)",
                    icon: success ? "trash.circle.fill" : "xmark.circle.fill"
                )
                self.refreshSnapshots()
            }
        }
    }
    
    private func refreshSnapshots() {
        manager.fetchDatabaseSnapshots { list in
            DispatchQueue.main.async {
                self.snapshots = list
            }
        }
    }

    private func checkForSettingsUpdate() {
        isCheckingForUpdate = true
        Task {
            do {
                let update = try await AppUpdateChecker.checkForUpdate()
                await MainActor.run {
                    self.isCheckingForUpdate = false
                    self.settingsUpdate = update
                    if let update {
                        self.showToastMessage(title: "ByeTunes \(update.version) is available", icon: "arrow.down.circle.fill")
                    } else {
                        self.showToastMessage(title: "ByeTunes is up to date", icon: "checkmark.circle.fill")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCheckingForUpdate = false
                    self.showToastMessage(title: "Update Check Failed", icon: "xmark.circle.fill")
                }
                Logger.shared.log("[Update] Settings version check failed: \(error.localizedDescription)")
            }
        }
    }

    private func fixArtwork() {
        isFixingArtwork = true
        updateArtworkFixProgress("Fixing artwork...")

        manager.repairIOS26ArtworkColors { message in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(message)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isFixingArtwork = false
                self.updateArtworkFixProgress(message)
                self.showToastMessage(
                    title: success ? message : "Artwork Fix Failed: \(message)",
                    icon: success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
            }
        }
    }

    private func updateArtworkFixProgress(_ message: String) {
        status = message
        artworkFixMessage = message.isEmpty ? "Fixing artwork..." : message
        artworkFixProgress = parsedArtworkFixProgress(from: message)
    }

    private func parsedArtworkFixProgress(from message: String) -> Double? {
        guard let range = message.range(of: #"(\d+)/(\d+)"#, options: .regularExpression) else {
            return nil
        }

        let parts = message[range].split(separator: "/")
        guard parts.count == 2,
              let current = Double(parts[0]),
              let total = Double(parts[1]),
              total > 0 else {
            return nil
        }

        return min(max(current / total, 0), 1)
    }
    
    private func formatSnapshotDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    
    private func showToastMessage(title: String, icon: String) {
        withAnimation(.spring()) {
            self.toastTitle = title
            self.toastIcon = icon
            self.showToast = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.showToast = false
            }
        }
    }
    
    func handlePairingImport(url: URL?) {
        guard let url = url else { return }
        
        do {
            try manager.importPairingFile(from: url)
            status = "\(manager.expectedPairingFileTitle) imported"
            
            manager.startHeartbeat()
        } catch {
            status = error.localizedDescription
        }
    }

    private var downloadFolderSubtitle: String {
        let directory = SongMetadata.persistentDownloadsDirectory()
        if SongMetadata.customPersistentDownloadsDirectory() != nil {
            return directory.lastPathComponent
        }
        return "App Folder"
    }

    private func handleDownloadFolderSelection(url: URL?) {
        guard let url else { return }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "downloadedSongsFolderBookmark")
            showToastMessage(title: "Download Folder Updated", icon: "folder.badge.checkmark")
        } catch {
            showToastMessage(title: "Folder Selection Failed", icon: "exclamationmark.triangle.fill")
        }
    }
}
