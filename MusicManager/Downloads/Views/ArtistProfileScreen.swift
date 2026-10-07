import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

struct ArtistProfileScreen: View {
    private enum ArtistSection: String {
        case albums = "Albums"
        case tracks = "Tracks"
    }

    let artist: DownloadArtist
    @ObservedObject var vm: DownloadViewModel
    let onSelectAlbum: (DownloadAlbum) -> Void
    let onBrowseTrack: (DownloadTrack) -> Void

    @State private var profile = DownloadArtistProfile(tracks: [], albums: [])
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var selectedSection: ArtistSection = .albums
    @State private var visibleAlbumCount = 8
    @State private var visibleTrackCount = 12

    private var hasResults: Bool {
        !profile.albums.isEmpty || !profile.tracks.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artistHeroHeader

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading artist profile...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    if hasResults {
                        artistSectionPicker
                            .padding(.horizontal, 20)
                    }

                    if selectedSection == .albums {
                        if !profile.albums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Albums & Singles")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(min(visibleAlbumCount, profile.albums.count))/\(profile.albums.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 14),
                                        GridItem(.flexible(), spacing: 14)
                                    ],
                                    spacing: 14
                                ) {
                                    ForEach(Array(profile.albums.prefix(visibleAlbumCount))) { album in
                                        artistAlbumCard(album)
                                    }
                                }
                                .padding(.horizontal, 20)

                                if visibleAlbumCount < profile.albums.count {
                                    artistLoadMoreButton(title: "Load More Albums") {
                                        visibleAlbumCount = min(visibleAlbumCount + 8, profile.albums.count)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    } else {
                        if !profile.tracks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Tracks")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(min(visibleTrackCount, profile.tracks.count))/\(profile.tracks.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)

                                VStack(spacing: 0) {
                                    ForEach(Array(profile.tracks.prefix(visibleTrackCount).enumerated()), id: \.element.id) { index, track in
                                        artistTrackRow(track)
                                        if index < min(visibleTrackCount, profile.tracks.count) - 1 {
                                            Divider().padding(.leading, 80)
                                        }
                                    }
                                }
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray5), lineWidth: 1)
                                )
                                .padding(.horizontal, 20)

                                if visibleTrackCount < profile.tracks.count {
                                    artistLoadMoreButton(title: "Load More Tracks") {
                                        visibleTrackCount = min(visibleTrackCount + 12, profile.tracks.count)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }

                    if profile.albums.isEmpty && profile.tracks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "music.mic")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("No artist results found")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Artist")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artist.id) {
            isLoading = true
            visibleAlbumCount = 8
            visibleTrackCount = 12
            selectedSection = .albums
            let loaded = await vm.loadArtistProfile(for: artist)
            profile = loaded
            errorText = (loaded.tracks.isEmpty && loaded.albums.isEmpty) ? "Could not load results for \(artist.name)." : nil
            if loaded.albums.isEmpty && !loaded.tracks.isEmpty {
                selectedSection = .tracks
            }
            isLoading = false
        }
    }

    private var artistHeroHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                AsyncImage(url: artist.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color(.secondarySystemFill)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.mic")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(artist.name)
                        .font(.system(size: 30, weight: .bold))
                    Text(artist.provider.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if hasResults {
                HStack(spacing: 10) {
                    artistCountPill(title: "Albums", value: profile.albums.count)
                    artistCountPill(title: "Tracks", value: profile.tracks.count)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func artistCountPill(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    private func artistLoadMoreButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var artistSectionPicker: some View {
        HStack(spacing: 8) {
            ForEach([ArtistSection.albums, .tracks], id: \.rawValue) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(spacing: 6) {
                        Text(section.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedSection == section ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedSection == section ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func artistAlbumCard(_ album: DownloadAlbum) -> some View {
        Button {
            onSelectAlbum(album)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: album.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(.tertiarySystemFill)
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(album.artistLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artistTrackRow(_ track: DownloadTrack) -> some View {
        HStack(spacing: 12) {
            Button {
                onBrowseTrack(track)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .lineLimit(1)
                            .font(.headline)
                        Text(track.artistLine)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(track.albumName)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                vm.togglePreview(for: track)
            } label: {
                if vm.isPreviewLoading(for: track.id) {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: vm.isPreviewPlaying(for: track.id) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(vm.isPreviewPlaying(for: track.id) ? .blue : .secondary)
                }
            }
            .buttonStyle(.plain)

            Button {
                if vm.state(for: track.id) == .failed {
                    vm.retry(trackID: track.id)
                } else {
                    vm.enqueue(track: track)
                }
            } label: {
                switch vm.state(for: track.id) {
                case .downloading:
                    ProgressView().frame(width: 28, height: 28)
                case .queued:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                case .idle:
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!vm.canEnqueue(trackID: track.id))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
