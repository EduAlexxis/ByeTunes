import SwiftUI
import UIKit

struct LibraryRepairView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var status: String

    @State private var isFixingArtwork = false
    @State private var isFixingAlphabeticalOrder = false
    @State private var isCreatingFavorites = false
    @State private var isFixingFavorites = false
    @State private var isDeletingFavorites = false
    @State private var showingDeleteFavoritesAlert = false
    @State private var showingReplaceFavoritesAlert = false
    @State private var isRebuildingAlbumArtwork = false
    @State private var isRunningRepairDoctor = false
    @State private var artworkFixMessage = "Fixing artwork..."
    @State private var artworkFixProgress: Double? = nil

    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""

    @State private var infoAlertTitle = ""
    @State private var infoAlertMessage = ""
    @State private var showingInfoAlert = false

    private func showInfo(_ title: String, _ message: String) {
        infoAlertTitle = title
        infoAlertMessage = message
        showingInfoAlert = true
    }

    private var infoButton: some View {
        Image(systemName: "info.circle")
            .font(.body)
            .foregroundColor(.secondary)
    }

    private var isExperimentalArtworkRefreshActive: Bool {
        isRebuildingAlbumArtwork && !isFixingArtwork
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LIBRARY REPAIR & MAINTENANCE")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                runDatabaseRepairDoctor()
                            } label: {
                                HStack {
                                    if isRunningRepairDoctor {
                                        ProgressView()
                                            .frame(width: 28)
                                    } else {
                                        Image(systemName: "heart.text.square")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isRunningRepairDoctor ? "Repairing Library..." : "Clean & Repair Library")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text("Scan for and fix invalid entries.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunningRepairDoctor || !manager.heartbeatReady)

                            Spacer()

                            Button {
                                showInfo(
                                    "Clean & Repair Library",
                                    "Scans your database for \"ghost\" songs (entries pointing to files that no longer exist) and resolves other invalid database entries that can cause missing songs or crashes."
                                )
                            } label: {
                                infoButton
                            }
                            .buttonStyle(.plain)

                            if !isRunningRepairDoctor {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray3))
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .opacity((isRunningRepairDoctor || !manager.heartbeatReady) ? 0.55 : 1)

                        Divider().padding(.leading, 56)

                        HStack {
                            Button {
                                fixAlphabeticalOrdering()
                            } label: {
                                HStack {
                                    if isFixingAlphabeticalOrder {
                                        ProgressView()
                                            .frame(width: 28)
                                    } else {
                                        Image(systemName: "textformat.abc")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isFixingAlphabeticalOrder ? "Fixing Alphabetical Order..." : "Fix Alphabetical Order")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Regroup titles under the right letters.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isFixingAlphabeticalOrder || !manager.heartbeatReady)

                            Spacer()

                            Button {
                                showInfo(
                                    "Fix Alphabetical Order",
                                    "Repairs broken song section ordering, so titles group under the right letters again in alphabetical lists instead of trailing off into the wrong section."
                                )
                            } label: {
                                infoButton
                            }
                            .buttonStyle(.plain)

                            if !isFixingAlphabeticalOrder {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray3))
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .opacity((isFixingAlphabeticalOrder || !manager.heartbeatReady) ? 0.55 : 1)

                        Divider().padding(.leading, 56)

                        HStack {
                            Button {
                                createFavoritesPlaylist()
                            } label: {
                                HStack {
                                    if isCreatingFavorites {
                                        ProgressView()
                                            .frame(width: 28)
                                    } else {
                                        Image(systemName: "heart.fill")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isCreatingFavorites ? "Creating Favorites Playlist..." : "Create Favorites Playlist")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Adds the Favorites playlist to Music.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isCreatingFavorites || !manager.heartbeatReady)

                            Spacer()

                            Button {
                                showInfo(
                                    "Create Favorites Playlist",
                                    "Adds the Favorites playlist to your Music library for devices that don't have one, such as when Sync Library is off. Songs you mark as favorites afterward appear in it. Songs favorited before creating it may need to be favorited again."
                                )
                            } label: {
                                infoButton
                            }
                            .buttonStyle(.plain)

                            if !isCreatingFavorites {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray3))
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .opacity((isCreatingFavorites || !manager.heartbeatReady) ? 0.55 : 1)

                        Divider().padding(.leading, 56)

                        HStack {
                            Button {
                                fixMissingFavorites()
                            } label: {
                                HStack {
                                    if isFixingFavorites {
                                        ProgressView()
                                            .frame(width: 28)
                                    } else {
                                        Image(systemName: "heart.circle")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isFixingFavorites ? "Fixing Missing Favorites..." : "Fix Missing Favorites")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Show non-Apple Music songs in Favorites.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isFixingFavorites || !manager.heartbeatReady)

                            Spacer()

                            Button {
                                showInfo(
                                    "Fix Missing Favorites",
                                    "Songs that aren't on Apple Music can be favorited but never show up in the Favorites playlist. This finds your favorited songs that are affected and gives them the details Music needs to list them. Run it again after favoriting more of these songs. If Sync Library is on, back up your library first."
                                )
                            } label: {
                                infoButton
                            }
                            .buttonStyle(.plain)

                            if !isFixingFavorites {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray3))
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .opacity((isFixingFavorites || !manager.heartbeatReady) ? 0.55 : 1)

                        Divider().padding(.leading, 56)

                        HStack {
                            Button {
                                showingDeleteFavoritesAlert = true
                            } label: {
                                HStack {
                                    if isDeletingFavorites {
                                        ProgressView()
                                            .frame(width: 28)
                                    } else {
                                        Image(systemName: "heart.slash")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isDeletingFavorites ? "Deleting Favorites Playlist..." : "Delete Favorites Playlist")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Removes the Favorites playlist from Music.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeletingFavorites || !manager.heartbeatReady)

                            Spacer()

                            Button {
                                showInfo(
                                    "Delete Favorites Playlist",
                                    "Removes the Favorites playlist from your Music library. Your songs and their favorite marks are not deleted, so creating the playlist again brings your favorites back."
                                )
                            } label: {
                                infoButton
                            }
                            .buttonStyle(.plain)

                            if !isDeletingFavorites {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray3))
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .opacity((isDeletingFavorites || !manager.heartbeatReady) ? 0.55 : 1)

                        if manager.supportsIOS26ArtworkRepair {
                            Divider().padding(.leading, 56)

                            HStack {
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
                                            Text("For songs added before iOS 26.4. Internet required.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isFixingArtwork || !manager.heartbeatReady)

                                Spacer()

                                Button {
                                    showInfo(
                                        "Fix Artwork",
                                        "Fixes artwork and extracted colors for songs added before iOS 26.4, when Apple changed how artwork is stored. Requires an internet connection to re-fetch artwork."
                                    )
                                } label: {
                                    infoButton
                                }
                                .buttonStyle(.plain)

                                if !isFixingArtwork {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemGray3))
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .opacity((isFixingArtwork || manager.heartbeatReady) ? 1 : 0.55)

                            Divider().padding(.leading, 56)

                            HStack {
                                Button {
                                    rebuildAlbumArtworkExperimental()
                                } label: {
                                    HStack {
                                        if isRebuildingAlbumArtwork {
                                            ProgressView()
                                                .frame(width: 28)
                                        } else {
                                            Image(systemName: "wrench.and.screwdriver")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .frame(width: 28)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(isRebuildingAlbumArtwork ? "Running Advanced Artwork & Metadata Fix..." : "Advanced Artwork & Metadata Fix")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("Deeper repair, can take a while. Internet required.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isRebuildingAlbumArtwork || !manager.heartbeatReady)

                                Spacer()

                                Button {
                                    showInfo(
                                        "Advanced Artwork & Metadata Fix",
                                        "An experimental, deeper repair pass for songs still missing artwork or metadata after the regular Fix Artwork pass. Rebuilds album artwork pointers directly using an internet connection. Can take a while for large libraries."
                                    )
                                } label: {
                                    infoButton
                                }
                                .buttonStyle(.plain)

                                if !isRebuildingAlbumArtwork {
                                    Image(systemName: "flask")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemOrange))
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .opacity((isRebuildingAlbumArtwork || manager.heartbeatReady) ? 1 : 0.55)
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )

                }
                .padding(16)
                .padding(.bottom, 120)
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
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }

            if isFixingArtwork || isRebuildingAlbumArtwork || isRunningRepairDoctor || isFixingAlphabeticalOrder || isCreatingFavorites || isFixingFavorites || isDeletingFavorites {
                artworkFixPopup
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isFixingArtwork)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isRebuildingAlbumArtwork)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isFixingAlphabeticalOrder)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCreatingFavorites)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isFixingFavorites)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isDeletingFavorites)
        .navigationTitle("Library Repair")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Favorites Playlist?", isPresented: $showingDeleteFavoritesAlert) {
            Button("Delete", role: .destructive) {
                deleteFavoritesPlaylist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Favorites playlist from Music. Your songs and favorite marks stay, and you can create the playlist again later.")
        }
        .alert("Replace Favorites Playlist?", isPresented: $showingReplaceFavoritesAlert) {
            Button("Replace", role: .destructive) {
                createFavoritesPlaylist(replaceExisting: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A Favorites playlist already exists. Replacing it removes it and creates a new one that includes songs added with ByeTunes. If Sync Library is on, the original cloud playlist may stop syncing.")
        }
        .alert(infoAlertTitle, isPresented: $showingInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoAlertMessage)
        }
    }

    private var artworkFixPopup: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: isDeletingFavorites ? "heart.slash" : isFixingFavorites ? "heart.circle" : isCreatingFavorites ? "heart.fill" : (isRunningRepairDoctor ? "heart.text.square" : (isFixingAlphabeticalOrder ? "textformat.abc.dottedunderline" : (isExperimentalArtworkRefreshActive ? "wand.and.stars" : "photo.on.rectangle.angled"))))
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 6) {
                    Text(isDeletingFavorites ? "Delete Favorites Playlist" : isFixingFavorites ? "Fix Missing Favorites" : isCreatingFavorites ? "Create Favorites Playlist" : (isRunningRepairDoctor ? "Clean & Repair Library" : (isFixingAlphabeticalOrder ? "Fix Alphabetical Order" : (isExperimentalArtworkRefreshActive ? "Refreshing Metadata & Artwork" : "Fixing Artwork"))))
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

                Button {
                    manager.cancelCurrentRepairOperation()
                    artworkFixMessage = "Cancelling..."
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                guard !message.lowercased().contains("cancel") else { return }
                self.updateArtworkFixProgress(message)
                self.showToastMessage(
                    title: success ? message : "Artwork Fix Failed: \(message)",
                    icon: success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
            }
        }
    }

    private func rebuildAlbumArtworkExperimental() {
        isRebuildingAlbumArtwork = true
        updateArtworkFixProgress("Running advanced artwork and metadata fix...")

        manager.repairExperimentalAlbumArtworkPointers { message in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(message)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isRebuildingAlbumArtwork = false
                guard !message.lowercased().contains("cancel") else { return }
                self.updateArtworkFixProgress(message)
                self.showToastMessage(
                    title: success ? message : "Advanced Artwork & Metadata Fix Failed: \(message)",
                    icon: success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
            }
        }
    }

    private func runDatabaseRepairDoctor() {
        isRunningRepairDoctor = true
        updateArtworkFixProgress("Starting library cleanup & repair...")

        manager.runDatabaseRepairDoctor { statusMessage, progressFraction in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(statusMessage)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isRunningRepairDoctor = false
                guard !message.lowercased().contains("cancel") else { return }
                if success {
                    self.showToastMessage(title: "Library Repaired!", icon: "shield.checkmark.fill")
                } else {
                    self.showToastMessage(title: "Repair Failed: \(message)", icon: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    private func fixAlphabeticalOrdering() {
        isFixingAlphabeticalOrder = true
        updateArtworkFixProgress("Preparing alphabetical order repair...")

        manager.fixAlphabeticalOrdering { message in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(message)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isFixingAlphabeticalOrder = false
                guard !message.lowercased().contains("cancel") else { return }
                self.showToastMessage(
                    title: success ? message : "Alphabetical Fix Failed: \(message)",
                    icon: success ? "textformat.abc.dottedunderline" : "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func createFavoritesPlaylist(replaceExisting: Bool = false) {
        isCreatingFavorites = true
        updateArtworkFixProgress("Preparing favorites playlist...")

        manager.createFavoritesPlaylist(replaceExisting: replaceExisting) { message in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(message)
            }
        } completion: { result in
            DispatchQueue.main.async {
                self.isCreatingFavorites = false
                switch result {
                case .alreadyExists:
                    self.showingReplaceFavoritesAlert = true
                case .created:
                    self.showToastMessage(title: "Favorites playlist created.", icon: "heart.fill")
                case .replaced(let refreshed):
                    self.showToastMessage(title: "Favorites playlist replaced. Refreshed \(refreshed) favorited songs.", icon: "heart.fill")
                case .failed(let message):
                    guard !message.lowercased().contains("cancel") else { return }
                    self.showToastMessage(title: "Favorites Playlist Failed: \(message)", icon: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    private func fixMissingFavorites() {
        isFixingFavorites = true
        updateArtworkFixProgress("Preparing favorites fix...")

        manager.fixMissingFavorites { message in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(message)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isFixingFavorites = false
                guard !message.lowercased().contains("cancel") else { return }
                self.showToastMessage(
                    title: success ? message : "Favorites Fix Failed: \(message)",
                    icon: success ? "heart.circle.fill" : "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func deleteFavoritesPlaylist() {
        isDeletingFavorites = true
        updateArtworkFixProgress("Preparing to delete favorites playlist...")

        manager.deleteFavoritesPlaylist { message in
            DispatchQueue.main.async {
                self.updateArtworkFixProgress(message)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isDeletingFavorites = false
                guard !message.lowercased().contains("cancel") else { return }
                self.showToastMessage(
                    title: success ? message : "Delete Failed: \(message)",
                    icon: success ? "heart.slash.fill" : "exclamationmark.triangle.fill"
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
}
