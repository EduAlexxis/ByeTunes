import SwiftUI

/// Lists favorites & ratings imported from the device's Music library.
struct ImportedFavoritesView: View {
    @ObservedObject private var store = DeviceFavoritesStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingClearAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if store.favorites.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No Imported Favorites")
                            .font(.headline)
                        Text("Use “Import Favorites & Ratings” in Library Tools to copy your loves, dislikes and star ratings from Music.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Favorites & Ratings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !store.favorites.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear", role: .destructive) { showingClearAlert = true }
                    }
                }
            }
            .alert("Clear Imported Favorites?", isPresented: $showingClearAlert) {
                Button("Clear", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only removes the saved copy in ByeTunes. Hearts and ratings in the Music app are not touched.")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.favorites) { favorite in
                    HStack(spacing: 12) {
                        Image(systemName: favorite.isLoved ? "heart.fill" : favorite.isDisliked ? "heart.slash.fill" : "star.fill")
                            .foregroundColor(favorite.isLoved ? .pink : favorite.isDisliked ? .secondary : .yellow)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.title)
                                .font(.body)
                                .lineLimit(1)
                            Text(subtitle(for: favorite))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if favorite.userRating > 0 {
                            HStack(spacing: 1) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text("\(favorite.userRating)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if favorite.playCount > 0 {
                            Text("\(favorite.playCount)×")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } footer: {
                Text("\(store.lovedCount) loved · \(store.ratedCount) rated. Re-injecting these songs keeps their hearts and ratings.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func subtitle(for favorite: DeviceFavorite) -> String {
        var parts: [String] = []
        if !favorite.artist.isEmpty { parts.append(favorite.artist) }
        if !favorite.album.isEmpty { parts.append(favorite.album) }
        if parts.isEmpty { parts.append("Unknown artist") }
        return parts.joined(separator: " — ")
    }
}
