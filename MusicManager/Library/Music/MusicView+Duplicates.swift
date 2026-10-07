import SwiftUI
import UniformTypeIdentifiers

extension MusicView {
    var duplicateReviewSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.orange.opacity(0.16))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.orange)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Possible Duplicates")
                                        .font(.title2.weight(.bold))
                                    Text("We found \(detectedDuplicates.count) tracks that look like duplicates. Keep selected ones, or skip them before import.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }

                            HStack(spacing: 10) {
                                duplicateStatChip(
                                    title: "Selected",
                                    value: "\(detectedDuplicates.filter { duplicateImportSelection[$0.incoming.id] ?? true }.count)"
                                )
                                duplicateStatChip(
                                    title: "Detected",
                                    value: "\(detectedDuplicates.count)"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )

                        HStack(spacing: 10) {
                            Button("Select All") {
                                for d in detectedDuplicates {
                                    duplicateImportSelection[d.incoming.id] = true
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())

                            Button("Deselect All") {
                                for d in detectedDuplicates {
                                    duplicateImportSelection[d.incoming.id] = false
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVStack(spacing: 12) {
                            ForEach(detectedDuplicates) { item in
                                Button {
                                    let current = duplicateImportSelection[item.incoming.id] ?? true
                                    duplicateImportSelection[item.incoming.id] = !current
                                } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill((duplicateImportSelection[item.incoming.id] ?? true) ? Color.accentColor : Color(.systemGray5))
                                                .frame(width: 30, height: 30)
                                            Image(systemName: (duplicateImportSelection[item.incoming.id] ?? true) ? "checkmark" : "circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor((duplicateImportSelection[item.incoming.id] ?? true) ? .white : Color(.systemGray3))
                                        }
                                        .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(duplicateDisplayFilename(for: item.incoming))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(2)

                                                Spacer(minLength: 8)

                                                Text("DUPLICATE")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundColor(.orange)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(Color.orange.opacity(0.12))
                                                    .clipShape(Capsule())
                                            }

                                            VStack(alignment: .leading, spacing: 8) {
                                                duplicateComparisonRow(
                                                    icon: "square.and.arrow.down",
                                                    title: "Incoming",
                                                    value: "\(item.incoming.artist) - \(item.incoming.title)"
                                                )
                                                duplicateComparisonRow(
                                                    icon: "music.note",
                                                    title: "Matches",
                                                    value: "\(item.matched.artist) - \(item.matched.title)"
                                                )
                                                HStack(spacing: 6) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.orange)
                                                    Text(item.reason)
                                                        .font(.caption2.weight(.medium))
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke((duplicateImportSelection[item.incoming.id] ?? true) ? Color.accentColor.opacity(0.24) : Color(.systemGray5), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                }
                .background(Color(.systemGroupedBackground))

                HStack(spacing: 12) {
                    Button {
                        finalizeImportedSongs(
                            songsToImport: pendingImportedSongs,
                            duplicateIDsToSkip: Set(detectedDuplicates.map { $0.incoming.id }),
                            includeDuplicates: false,
                            initialSkippedCount: pendingImportSkippedCount,
                            alreadyImportedCount: pendingAlreadyImportedCount
                        )
                        clearPendingDuplicateState()
                    } label: {
                        Text("Skip Duplicates")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        let duplicateIDsToSkip = Set(
                            detectedDuplicates
                                .filter { !(duplicateImportSelection[$0.incoming.id] ?? true) }
                                .map { $0.incoming.id }
                        )
                        finalizeImportedSongs(
                            songsToImport: pendingImportedSongs,
                            duplicateIDsToSkip: duplicateIDsToSkip,
                            includeDuplicates: false,
                            initialSkippedCount: pendingImportSkippedCount,
                            alreadyImportedCount: pendingAlreadyImportedCount
                        )
                        clearPendingDuplicateState()
                    } label: {
                        Text("Import Selected")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .background(Color(.systemBackground))
                .overlay(alignment: .top) {
                    Divider()
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Duplicate Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearPendingDuplicateState()
                        showToast(title: "Import cancelled", icon: "xmark.circle.fill")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    func duplicateStatChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func duplicateComparisonRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
    }

    func duplicateDisplayFilename(for song: SongMetadata) -> String {
        let originalName = song.localURL.deletingPathExtension().lastPathComponent
        let cleanedName = originalName.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}_"#,
            with: "",
            options: .regularExpression
        )
        let ext = song.localURL.pathExtension
        return ext.isEmpty ? cleanedName : "\(cleanedName).\(ext)"
    }

    func duplicateSignature(for song: SongMetadata) -> String {
        "\(normalizeDuplicateField(song.title))|\(normalizeDuplicateField(song.artist))|\(normalizeDuplicateField(song.album))"
    }

    func normalizeDuplicateField(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func finalizeImportedSongs(
        songsToImport: [SongMetadata],
        duplicateIDsToSkip: Set<UUID>,
        includeDuplicates: Bool,
        initialSkippedCount: Int,
        alreadyImportedCount: Int = 0
    ) {
        let acceptedSongs: [SongMetadata]
        let duplicateSkipped = duplicateIDsToSkip.count

        if includeDuplicates {
            acceptedSongs = songsToImport
        } else {
            acceptedSongs = songsToImport.filter { !duplicateIDsToSkip.contains($0.id) }
            let skippedSongs = songsToImport.filter { duplicateIDsToSkip.contains($0.id) }
            for song in skippedSongs {
                if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                    try? FileManager.default.removeItem(at: song.localURL)
                }
            }
        }

        let totalImported = alreadyImportedCount + acceptedSongs.count

        if !acceptedSongs.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) {
                songs.append(contentsOf: acceptedSongs)
            }
        }

        if totalImported > 0 {
            let totalSkipped = initialSkippedCount + duplicateSkipped
            let title: String
            if totalSkipped > 0 {
                title = "Imported \(totalImported), Skipped \(totalSkipped)"
            } else {
                title = totalImported == 1 ? "Imported 1 Song" : "Imported \(totalImported) Songs"
            }
            showToast(title: title, icon: "checkmark.circle.fill")
        } else {
            Logger.shared.log("[MusicView] No songs imported from selection")
            showToast(title: "No songs imported", icon: "exclamationmark.triangle")
        }
    }

    func clearPendingDuplicateState() {
        pendingImportedSongs.removeAll()
        pendingAlreadyImportedCount = 0
        detectedDuplicates.removeAll()
        duplicateImportSelection.removeAll()
        pendingImportSkippedCount = 0
        showingDuplicateSheet = false
    }
}
