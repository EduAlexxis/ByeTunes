import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct AddSongsToPlaylistSheet: View {
    let allSongs: [DeviceManager.ExportableSongInfo]
    let playlistPid: Int64
    let onAdd: ([Int64]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPids = Set<Int64>()
    @State private var searchText = ""
    
    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.white
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
    
    var filteredSongs: [DeviceManager.ExportableSongInfo] {
        if searchText.isEmpty { return allSongs }
        return allSongs.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) }
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
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredSongs.enumerated()), id: \.element.itemPid) { index, song in
                                Button {
                                    if selectedPids.contains(song.itemPid) {
                                        selectedPids.remove(song.itemPid)
                                    } else {
                                        selectedPids.insert(song.itemPid)
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
                                        if selectedPids.contains(song.itemPid) {
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
                                
                                if index < filteredSongs.count - 1 {
                                    Divider().background(hairlineColor).padding(.leading, 20)
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
                        onAdd(Array(selectedPids))
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                    .disabled(selectedPids.isEmpty)
                }
            }
        }
    }
}
