import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var status: String
    
    @State private var showingPairingPicker = false
    @State private var showingDeleteAlert = false
    
    
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    @AppStorage("metadataSource") private var metadataSource = "local"
    @AppStorage("autofetchMetadata") private var autofetchMetadata = true
    @AppStorage("storeRegion") private var storeRegion = "US"
    
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
                                    Text("Pairing File")
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
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            
                            Text("Version")
                                .font(.body)
                            
                            Spacer()
                            
                            Text("1.0.0")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
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
                            
                            Text("M4R, MP3")
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
                                Text("Custom").tag("custom")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        
                        if metadataSource == "itunes" || metadataSource == "deezer" {
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
        .alert("Delete Library?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                
                manager.deleteMediaLibrary { success in
                    DispatchQueue.main.async {
                        
                        
                        if success {
                           self.showToast(title: "Library Deleted", icon: "trash.circle.fill")
                        } else {
                           self.showToast(title: "Deletion Failed", icon: "exclamationmark.triangle.fill")
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently delete your Music library database and playlists from the device. This action cannot be undone.")
        }
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
    }

    

    private func showToast(title: String, icon: String) {
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
        
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let destination = manager.pairingFile
        
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            
            status = "Pairing file imported"
            
            
            manager.startHeartbeat()
        } catch {
            status = "Import failed"
        }
    }
}
