import SwiftUI
import UniformTypeIdentifiers

struct DownloaderSettingsScreen: View {
    @Binding var metadataSource: String
    @Binding var autofetchMetadata: Bool
    @Binding var keepLocalMetadataForLocalFiles: Bool
    @Binding var fetchLyrics: Bool
    @Binding var appleSubscriptionLyrics: Bool
    @Binding var storeRegion: String
    @Binding var appleRichMetadata: Bool
    @Binding var downloadSearchProvider: String
    @Binding var keepDownloadedSongs: Bool
    @Binding var tagKeptDownloadedSongs: Bool
    @Binding var backgroundDownloadsEnabled: Bool
    @AppStorage("silentAudioEnabled") var silentAudioEnabled = true
    @AppStorage("pictureInPictureEnabled") var pictureInPictureEnabled = true
    @AppStorage("locationKeepAliveEnabled") var locationKeepAliveEnabled = false
    @Binding var showingDownloadFolderPicker: Bool
    @Binding var yoinkifyFormat: String

    let downloadFolderSubtitle: String

    @State var infoAlertTitle = ""
    @State var infoAlertMessage = ""
    @State var showingInfoAlert = false

    func showInfo(_ title: String, _ message: String) {
        infoAlertTitle = title
        infoAlertMessage = message
        showingInfoAlert = true
    }

    var infoButton: some View {
        Image(systemName: "info.circle")
            .font(.body)
            .foregroundColor(.secondary)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                    metadataSection

                    downloadsSection

                    formatSection

                    }
                    .frame(width: max(proxy.size.width - 40, 0), alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .frame(width: proxy.size.width, alignment: .topLeading)
                .clipped()
            }
        }
        .navigationTitle("Metadata & Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .alert(infoAlertTitle, isPresented: $showingInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoAlertMessage)
        }
    }

}
