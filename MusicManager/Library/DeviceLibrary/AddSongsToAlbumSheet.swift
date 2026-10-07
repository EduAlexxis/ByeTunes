import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct AddSongsToAlbumSheet: View {
    let album: DeviceLibraryBrowserView.AlbumEntry
    let candidateSongs: [DeviceManager.ExportableSongInfo]
    let suggestedSongs: [DeviceManager.ExportableSongInfo]
    let onAdd: ([DeviceManager.ExportableSongInfo]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIDs = Set<String>()
    @State private var searchText = ""

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)
    }

    private var controlFillColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)
    }

    private func matches(_ song: DeviceManager.ExportableSongInfo) -> Bool {
        searchText.isEmpty || song.title.localizedCaseInsensitiveContains(searchText) || song.artist.localizedCaseInsensitiveContains(searchText)
    }

    private var remainingSongs: [DeviceManager.ExportableSongInfo] {
        let suggestedIDs = Set(suggestedSongs.map(\.id))
        return candidateSongs
            .filter { !suggestedIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var filteredSuggested: [DeviceManager.ExportableSongInfo] {
        suggestedSongs.filter(matches)
    }

    private var filteredRemaining: [DeviceManager.ExportableSongInfo] {
        remainingSongs.filter(matches)
    }

    @ViewBuilder
    private func songRow(_ song: DeviceManager.ExportableSongInfo) -> some View {
        Button {
            if selectedIDs.contains(song.id) {
                selectedIDs.remove(song.id)
            } else {
                selectedIDs.insert(song.id)
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                        .lineLimit(1)
                }
                Spacer()
                if selectedIDs.contains(song.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                } else {
                    Circle()
                        .stroke(mutedTextColor, lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(mutedTextColor)
                        TextField("Search songs", text: $searchText)
                            .foregroundStyle(strongTextColor)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(controlFillColor))
                    .padding()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !filteredSuggested.isEmpty {
                                Text("Suggested")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(mutedTextColor)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                                ForEach(Array(filteredSuggested.enumerated()), id: \.element.id) { index, song in
                                    songRow(song)
                                    if index < filteredSuggested.count - 1 {
                                        Divider().background(hairlineColor).padding(.leading, 20)
                                    }
                                }
                            }

                            if !filteredRemaining.isEmpty {
                                Text("All Songs")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(mutedTextColor)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                                ForEach(Array(filteredRemaining.enumerated()), id: \.element.id) { index, song in
                                    songRow(song)
                                    if index < filteredRemaining.count - 1 {
                                        Divider().background(hairlineColor).padding(.leading, 20)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd(candidateSongs.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}
