import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Controls
extension DeviceLibraryBrowserView {
    func topBarIconButton(systemName: String, showsProgress: Bool = false) -> some View {
        ZStack {
            Circle()
                .fill(controlFillColor)
                .frame(width: 44, height: 44)

            if showsProgress {
                ProgressView()
                    .tint(strongTextColor)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(strongTextColor)
            }
        }
        .compositingGroup()
    }

    var libraryModeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(LibraryMode.allCases) { mode in
                Button {
                    libraryMode = mode
                } label: {
                    VStack(spacing: 6) {
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(libraryMode == mode ? strongTextColor : mutedTextColor)

                        Rectangle()
                            .fill(libraryMode == mode ? Color.accentColor : Color.clear)
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
    }

    func actionCapsule(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDestructive: Bool = false,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isDestructive ? Color(red: 1.0, green: 0.27, blue: 0.42) : strongTextColor)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(hairlineColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    var sortMenu: some View {
        Menu {
            ForEach(SongSortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    if sortOption == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sort: \(sortOption.rawValue)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(strongTextColor)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(hairlineColor, lineWidth: 1)
                    )
            )
        }
        .disabled(isLoading || filteredSongs.isEmpty)
        .opacity(isLoading || filteredSongs.isEmpty ? 0.45 : 1)
    }

    var genreFilterMenu: some View {
        Menu {
            Button {
                selectedGenre = Self.allGenresOption
            } label: {
                if selectedGenre == Self.allGenresOption {
                    Label(Self.allGenresOption, systemImage: "checkmark")
                } else {
                    Text(Self.allGenresOption)
                }
            }

            ForEach(availableGenres, id: \.self) { genre in
                Button {
                    selectedGenre = genre
                } label: {
                    if selectedGenre == genre {
                        Label(genre, systemImage: "checkmark")
                    } else {
                        Text(genre)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(selectedGenre == Self.allGenresOption ? "Genre" : selectedGenre)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selectedGenre == Self.allGenresOption ? strongTextColor : Color.accentColor)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(selectedGenre == Self.allGenresOption ? hairlineColor : Color.accentColor, lineWidth: 1)
                    )
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.45 : 1)
    }
}
