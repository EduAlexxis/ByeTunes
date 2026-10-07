import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct AddToPlaylistView: View {
    let playlists: [DeviceLibraryBrowserView.PlaylistEntry]
    let onSelect: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        if playlists.isEmpty {
                            Text("No playlists found.")
                                .foregroundStyle(mutedTextColor)
                                .padding(.top, 40)
                        } else {
                            ForEach(Array(playlists.enumerated()), id: \.element.pid) { index, playlist in
                                Button {
                                    onSelect(playlist.pid)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(controlFillColor)
                                                .frame(width: 48, height: 48)
                                            Image(systemName: "music.note.list")
                                                .font(.title3)
                                                .foregroundStyle(mutedTextColor)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(playlist.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(strongTextColor)
                                            Text("\(playlist.songs.count) songs")
                                                .font(.subheadline)
                                                .foregroundStyle(mutedTextColor)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 20)
                                    .background(panelBackground)
                                }
                                .buttonStyle(.plain)
                                
                                if index < playlists.count - 1 {
                                    Divider()
                                        .background(hairlineColor)
                                        .padding(.leading, 82)
                                }
                            }
                        }
                    }
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding()
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                }
            }
        }
    }
}
