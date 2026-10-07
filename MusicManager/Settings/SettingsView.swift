import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    // MARK: - State
    @Environment(\.openURL) var openURL
    @ObservedObject var manager: DeviceManager
    @Binding var status: String

    @State var showingPairingPicker = false
    @State var showingDownloadFolderPicker = false
    @State var showingDeleteAlert = false

    @State var showingLogViewer = false
    @State var exportedDbURLs: [URL] = []
    @State var showingDbExportSheet = false
    @State var isExportingDb = false
    @State var isCheckingForUpdate = false
    @State var settingsUpdate: AppUpdateInfo?
    @State var supporters: [String] = []
    @State var supportersLoaded = false

    @State var showToast = false
    @State var toastTitle = ""
    @State var toastIcon = ""

    @AppStorage("metadataSource") var metadataSource = "apple"
    @AppStorage("autofetchMetadata") var autofetchMetadata = true
    @AppStorage("keepLocalMetadataForLocalFiles") var keepLocalMetadataForLocalFiles = false
    @AppStorage("fetchLyrics") var fetchLyrics = false
    @AppStorage("appleSubscriptionLyrics") var appleSubscriptionLyrics = false
    @AppStorage("storeRegion") var storeRegion = "US"
    @AppStorage("appleRichMetadata") var appleRichMetadata = true
    @AppStorage("keepDownloadedSongs") var keepDownloadedSongs = false
    @AppStorage("tagKeptDownloadedSongs") var tagKeptDownloadedSongs = false
    @AppStorage("backgroundDownloadsEnabled") var backgroundDownloadsEnabled = false
    @AppStorage("downloadSearchProvider") var downloadSearchProvider = DownloadSearchProviderOption.deezer.rawValue
    @AppStorage("yoinkifyFormat") var yoinkifyFormat = "flac"

    // MARK: - Body
    var body: some View {
        NavigationStack {
        ZStack(alignment: .bottom) {

        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {

                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 8)

                connectionSection

                repairSection

                downloadsSection

                deviceLibrarySection

                backupSection

                shortcutsSection

                helpSection

                debugSection

                supportSection

                aboutSection

                creditsSection

                dangerSection

                }
                .frame(width: max(proxy.size.width - 40, 0), alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
                }
                .frame(width: proxy.size.width, alignment: .topLeading)
                .clipped()
            }
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
            if downloadSearchProvider == DownloadSearchProviderOption.tidal.rawValue || downloadSearchProvider == DownloadSearchProviderOption.spotify.rawValue {
                downloadSearchProvider = DownloadSearchProviderOption.appleMusic.rawValue
            }
            if downloadSearchProvider == DownloadSearchProviderOption.metadata.rawValue {
                downloadSearchProvider = DownloadSearchProviderOption.itunes.rawValue
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
        }

        }
        .animation(.spring(), value: showToast)
        }
    }
}
