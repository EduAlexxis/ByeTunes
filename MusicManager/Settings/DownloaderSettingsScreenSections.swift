import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sections
extension DownloaderSettingsScreen {
    @ViewBuilder
    var metadataSection: some View {
        Text("METADATA")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .tracking(0.5)

        VStack(spacing: 0) {
            serverPickerRow(
                icon: "wand.and.stars",
                title: "Import Metadata Source",
                subtitle: "How imported songs get matched.",
                info: "Choose which service ByeTunes uses to look up metadata for songs you import. Local Files uses only what's already tagged on the file; iTunes, Deezer, and Apple Music look up matches online to fill in and correct title, artist, album, and artwork. Deezer lookups are limited to the US catalog.",
                selection: $metadataSource,
                options: MetadataSourceOption.allCases
            )

            Divider().padding(.leading, 56)

            Toggle(isOn: $keepLocalMetadataForLocalFiles) {
                HStack {
                    Image(systemName: "lock.doc")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Local Metadata")
                            .font(.body)
                        Text("Don't fetch metadata for imported local files.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showInfo(
                            "Keep Local Metadata",
                            "When on, songs you import from local files (e.g. from Files or the share sheet) keep exactly the tags already on the file. None of the settings below are applied to them: no online lookup, no rich Apple metadata, no lyrics fetch. This has no effect on songs from the Download tab."
                        )
                    } label: {
                        infoButton
                    }
                    .buttonStyle(.plain)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)

            if metadataSource != "apple" {
                Divider().padding(.leading, 56)

                Toggle(isOn: $appleRichMetadata) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.body)
                            .foregroundColor(.orange)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rich Apple Metadata")
                                .font(.body)
                            Text("Extra Apple-specific metadata.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Rich Apple Metadata",
                                "Also fetches Apple's internal Store ID, XID, and copyright details for matched songs. Useful for advanced metadata completeness, not required for normal playback."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }

            if metadataSource == "itunes" || metadataSource == "deezer" || metadataSource == "apple" {
                Divider().padding(.leading, 56)

                Toggle(isOn: $autofetchMetadata) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Autofetch")
                                .font(.body)
                            Text("Fetch metadata on import.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Autofetch",
                                "Automatically looks up and fills in metadata, using the source selected above, as soon as a song is imported, so you don't need to fetch it manually."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }

            if !appleSubscriptionLyrics {
                Divider().padding(.leading, 56)

                Toggle(isOn: $fetchLyrics) {
                    HStack {
                        Image(systemName: "quote.bubble.fill")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fetch Lyrics")
                                .font(.body)
                            Text("Automatically fetch lyrics.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Fetch Lyrics",
                                "Looks up lyrics automatically when importing or downloading a song. Tries LRCLIB first, then falls back to Musixmatch, then NetEase if the earlier sources don't have a match."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }

            Divider().padding(.leading, 56)

            Toggle(isOn: $appleSubscriptionLyrics) {
                HStack {
                    Image(systemName: "music.note.list")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music Subscription Lyrics")
                            .font(.body)
                        Text("Use Apple Music's synced lyrics.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showInfo(
                            "Apple Music Subscription Lyrics",
                            "If you have an active Apple Music subscription, use Apple's own time-synced lyrics instead of the community sources above. Requires an internet connection."
                        )
                    } label: {
                        infoButton
                    }
                    .buttonStyle(.plain)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)

            if metadataSource == "itunes" || metadataSource == "apple" || (metadataSource == "local" && appleRichMetadata) {
                Divider().padding(.leading, 56)

                NavigationLink {
                    RegionPickerScreen(selection: $storeRegion)
                } label: {
                    HStack {
                        Image(systemName: "globe")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Store Region")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Storefront for iTunes and Apple Music lookups.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(MetadataStoreRegionOption(rawValue: storeRegion).description)
                            .font(.body)
                            .foregroundColor(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    @ViewBuilder
    var downloadsSection: some View {
        Text("DOWNLOADS")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .tracking(0.5)

        VStack(spacing: 0) {
            serverPickerRow(
                icon: "magnifyingglass",
                title: "Search Source",
                subtitle: "Where the Download tab searches.",
                info: "Choose which service the Download tab searches for songs: Apple Music, iTunes, or Deezer.",
                selection: $downloadSearchProvider,
                options: DownloadSearchProviderOption.allCases
            )

            Divider().padding(.leading, 56)

            Toggle(isOn: $keepDownloadedSongs.animation(.easeInOut(duration: 0.2))) {
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Downloaded Songs")
                            .font(.body)
                        Text("Save downloads to this device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showInfo(
                            "Keep Downloaded Songs",
                            "When on, downloaded songs are saved locally in the app's Documents folder, so they're available offline and can be added to your device library. Turn off to skip keeping a local copy."
                        )
                    } label: {
                        infoButton
                    }
                    .buttonStyle(.plain)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)

            if keepDownloadedSongs {
                Divider().padding(.leading, 56)

                Toggle(isOn: $tagKeptDownloadedSongs) {
                    HStack {
                        Image(systemName: "tag")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save With Fetched Metadata")
                                .font(.body)
                            Text("Write the fetched tags and cover into kept files.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Save With Fetched Metadata",
                                "When on, the copies kept in the app's Documents folder get the metadata ByeTunes fetched (title, artist, album, genre, year, track and disc numbers, lyrics and cover art) written into the file, so it shows up correctly in other apps. Works for FLAC and MP3; other formats are kept as downloaded. Note: FLAC files can't render artwork on iOS, so the cover won't show on a FLAC file in iOS even though it is embedded. Turn off to keep the original file untouched."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .transition(.opacity)
            }

            Divider().padding(.leading, 56)

            Toggle(isOn: $backgroundDownloadsEnabled) {
                HStack {
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow Background Downloads")
                            .font(.body)
                        Text("Keep downloading when you leave the app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showInfo(
                            "Allow Background Downloads",
                            "While downloads are running and you leave the app, the app uses the options below to stay running so the whole queue keeps downloading: silent audio, a small Picture in Picture window with the download progress, and low-power location. Turn on the ones that work best for you."
                        )
                    } label: {
                        infoButton
                    }
                    .buttonStyle(.plain)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)

            if backgroundDownloadsEnabled {
                Divider().padding(.leading, 56)

                Toggle(isOn: $pictureInPictureEnabled) {
                    HStack {
                        Image(systemName: "pip")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Picture in Picture")
                                .font(.body)
                            Text("Floating progress window with silent audio.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Picture in Picture",
                                "Shows a small floating window with the download progress when you leave the app and plays silent audio so downloads keep running, even with the screen off. This is the most reliable option. Turn it off to choose Silent Audio and Keep Location Active yourself."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 56)

                Toggle(isOn: pictureInPictureEnabled ? .constant(true) : $silentAudioEnabled) {
                    HStack {
                        Image(systemName: "speaker.wave.1")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Silent Audio")
                                .font(.body)
                            Text(pictureInPictureEnabled ? "Included with Picture in Picture." : "Play silence so iOS keeps the app running.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Silent Audio",
                                "Plays an inaudible looping sound while downloads run so iOS keeps the app alive in the background. It mixes with your music and does not show a Now Playing card. It is always on with Picture in Picture, and can be used together with Keep Location Active when Picture in Picture is off."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .disabled(pictureInPictureEnabled)
                .opacity(pictureInPictureEnabled ? 0.55 : 1)

                Divider().padding(.leading, 56)

                Toggle(isOn: pictureInPictureEnabled ? .constant(false) : $locationKeepAliveEnabled) {
                    HStack {
                        Image(systemName: "location")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep Location Active")
                                .font(.body)
                            Text(pictureInPictureEnabled ? "Available when Picture in Picture is off." : "Helps downloads keep running in the background.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            showInfo(
                                "Keep Location Active",
                                "Uses low-power location updates while downloads run so iOS is less likely to pause the app. Your location is never stored or sent anywhere. iOS shows its location indicator while this is active, and it can use some extra battery. You will be asked to allow location access the first time. Available when Picture in Picture is off."
                            )
                        } label: {
                            infoButton
                        }
                        .buttonStyle(.plain)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .disabled(pictureInPictureEnabled)
                .opacity(pictureInPictureEnabled ? 0.55 : 1)
                .onChange(of: locationKeepAliveEnabled) { isOn in
                    if isOn {
                        LocationKeepAlive.shared.requestPermissionIfNeeded()
                    }
                }
            }

            if backgroundDownloadsEnabled && pictureInPictureEnabled {
                Divider().padding(.leading, 56)

                NavigationLink {
                    PictureInPictureCustomizeScreen()
                } label: {
                    HStack {
                        Image(systemName: "paintpalette")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Customize Picture in Picture")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Colors, background and Next Up rows.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }

            if keepDownloadedSongs {
                Divider().padding(.leading, 56)

                HStack {
                    Button {
                        showingDownloadFolderPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download Folder")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(downloadFolderSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        showInfo("Download Folder", "Choose where downloaded song files are saved on this device.")
                    } label: {
                        infoButton
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingDownloadFolderPicker = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    @ViewBuilder
    var formatSection: some View {
        Text("DOWNLOAD FORMAT")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.top, 8)

        VStack(spacing: 0) {
            serverPickerRow(
                icon: "sparkles.rectangle.stack",
                title: "Output Format",
                subtitle: "FLAC/ALAC when available, MP3 otherwise.",
                info: "FLAC and ALAC are lossless, but only available when a track is sourced from Deezer or Tidal. If a track isn't available lossless there, a 320kbps MP3 is downloaded instead automatically, and the queue will note when this happens for a specific song.",
                selection: $yoinkifyFormat,
                options: DownloaderYoinkifyFormatOption.allCases
            )
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    func serverPickerRow<Option: Identifiable & CustomStringConvertible>(
        icon: String,
        title: String,
        subtitle: String,
        info: String? = nil,
        selection: Binding<String>,
        options: [Option]
    ) -> some View where Option: RawRepresentable, Option.RawValue == String {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let info {
                Button {
                    showInfo(title, info)
                } label: {
                    infoButton
                }
                .buttonStyle(.plain)
            }

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.description).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

}
