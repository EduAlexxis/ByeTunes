import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct AddToAlbumView: View {
    let albums: [DeviceLibraryBrowserView.AlbumEntry]
    let onSelectAlbum: (DeviceLibraryBrowserView.AlbumEntry) -> Void
    let onCreateNewAlbum: (_ artist: String, _ album: String, _ genre: String, _ year: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNewAlbumForm = false
    @State private var newAlbumName = ""
    @State private var newAlbumArtist = ""
    @State private var newAlbumGenre = ""
    @State private var newAlbumYear = ""

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
                    VStack(spacing: 16) {
                        if showingNewAlbumForm {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Album name", text: $newAlbumName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Album artist", text: $newAlbumArtist)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Genre", text: $newAlbumGenre)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Year", text: $newAlbumYear)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    onCreateNewAlbum(
                                        newAlbumArtist,
                                        newAlbumName,
                                        newAlbumGenre,
                                        Int(newAlbumYear.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                                    )
                                    dismiss()
                                } label: {
                                    Text("Create Album")
                                        .font(.body.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(red: 1.0, green: 0.27, blue: 0.42))
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding()
                            .background(panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        } else {
                            Button {
                                showingNewAlbumForm = true
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(controlFillColor)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundStyle(mutedTextColor)
                                    }
                                    Text("New Album")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(strongTextColor)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20)
                                .background(panelBackground)
                            }
                            .buttonStyle(.plain)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        }

                        VStack(spacing: 0) {
                            if albums.isEmpty {
                                Text("No albums found.")
                                    .foregroundStyle(mutedTextColor)
                                    .padding(.top, 40)
                            } else {
                                ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                                    Button {
                                        onSelectAlbum(album)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(controlFillColor)
                                                    .frame(width: 48, height: 48)
                                                Image(systemName: "square.stack")
                                                    .font(.title3)
                                                    .foregroundStyle(mutedTextColor)
                                            }

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(album.name)
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(strongTextColor)
                                                    .lineLimit(1)
                                                Text("\(album.artist) · \(album.songs.count) track\(album.songs.count == 1 ? "" : "s")")
                                                    .font(.subheadline)
                                                    .foregroundStyle(mutedTextColor)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 20)
                                        .background(panelBackground)
                                    }
                                    .buttonStyle(.plain)

                                    if index < albums.count - 1 {
                                        Divider()
                                            .background(hairlineColor)
                                            .padding(.leading, 82)
                                    }
                                }
                            }
                        }
                        .background(panelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Add to Album")
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
