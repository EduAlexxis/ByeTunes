import SwiftUI

struct SmartPlaylistRule: Codable, Equatable {
    enum Kind: String, Codable {
        case genre
        case decade
        case explicitRating
        case artist
        case fileFormat
    }

    let kind: Kind
    let values: [String]

    func matchingSongs(in songs: [DeviceManager.ExportableSongInfo]) -> [DeviceManager.ExportableSongInfo] {
        switch kind {
        case .genre:
            let set = Set(values)
            return songs.filter { set.contains($0.genre.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .decade:
            let decades = Set(values.compactMap { Int($0) })
            return songs.filter { $0.year > 0 && decades.contains(($0.year / 10) * 10) }
        case .explicitRating:
            let ratings = Set(values.compactMap { Int($0) })
            return songs.filter { ratings.contains($0.explicitRating) }
        case .artist:
            let set = Set(values)
            return songs.filter { song in
                !set.isDisjoint(with: DeviceLibraryBrowserView.splitArtistNames(song.artist))
            }
        case .fileFormat:
            let set = Set(values.map { $0.lowercased() })
            return songs.filter { set.contains($0.fileExtension.lowercased()) }
        }
    }
}

struct SmartPlaylistBuilderView: View {
    let songs: [DeviceManager.ExportableSongInfo]
    let onCreate: (String, [Int64], SmartPlaylistRule, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private static let losslessFormats: Set<String> = ["FLAC", "ALAC", "WAV", "AIFF", "AIF"]

    private enum RuleType: String, CaseIterable, Identifiable {
        case genre = "Genre"
        case artist = "Artist"
        case decade = "Decade"
        case format = "Format"
        case explicitRating = "Explicit"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .genre: return "music.note"
            case .artist: return "person.fill"
            case .decade: return "calendar"
            case .format: return "waveform"
            case .explicitRating: return "checkmark.shield"
            }
        }

        var usesSearch: Bool {
            self == .genre || self == .artist
        }
    }

    private enum ExplicitChoice: String, CaseIterable, Identifiable, Hashable {
        case explicit = "Explicit Only"
        case clean = "Clean Only"
        case unrated = "No Rating"
        var id: String { rawValue }
        var ratingValue: Int {
            switch self {
            case .explicit: return 1
            case .clean: return 2
            case .unrated: return 0
            }
        }
    }

    @State private var ruleType: RuleType = .genre
    @State private var selectedGenres: Set<String> = []
    @State private var selectedArtists: Set<String> = []
    @State private var selectedDecades: Set<Int> = []
    @State private var selectedFormats: Set<String> = []
    @State private var selectedExplicitChoices: Set<ExplicitChoice> = []
    @State private var searchText: String = ""

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

    private var accentPink: Color { Color(red: 1.0, green: 0.27, blue: 0.42) }

    private func normalizedGenre(_ song: DeviceManager.ExportableSongInfo) -> String {
        song.genre.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedFormat(_ song: DeviceManager.ExportableSongInfo) -> String {
        song.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var genreCounts: [(genre: String, count: Int)] {
        let genres = songs.map(normalizedGenre).filter { !$0.isEmpty }
        let counts = Dictionary(grouping: genres, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }.map { (genre: $0.key, count: $0.value) }
    }

    private var artistCounts: [(artist: String, count: Int)] {
        var counts: [String: Int] = [:]
        for song in songs {
            for name in DeviceLibraryBrowserView.splitArtistNames(song.artist) {
                counts[name, default: 0] += 1
            }
        }
        return counts.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }.map { (artist: $0.key, count: $0.value) }
    }

    private var decadeCounts: [(decade: Int, count: Int)] {
        let decades = songs.compactMap { song -> Int? in
            guard song.year > 0 else { return nil }
            return (song.year / 10) * 10
        }
        let counts = Dictionary(grouping: decades, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.key > $1.key }.map { (decade: $0.key, count: $0.value) }
    }

    private var formatCounts: [(format: String, count: Int)] {
        let formats = songs.map(normalizedFormat).filter { !$0.isEmpty }
        let counts = Dictionary(grouping: formats, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.key < $1.key }.map { (format: $0.key, count: $0.value) }
    }

    private var explicitCounts: [ExplicitChoice: Int] {
        var result: [ExplicitChoice: Int] = [:]
        for choice in ExplicitChoice.allCases {
            result[choice] = songs.filter { $0.explicitRating == choice.ratingValue }.count
        }
        return result
    }

    private var filteredGenreCounts: [(genre: String, count: Int)] {
        guard !searchText.isEmpty else { return genreCounts }
        return genreCounts.filter { $0.genre.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredArtistCounts: [(artist: String, count: Int)] {
        guard !searchText.isEmpty else { return artistCounts }
        return artistCounts.filter { $0.artist.localizedCaseInsensitiveContains(searchText) }
    }

    private var currentRule: SmartPlaylistRule? {
        switch ruleType {
        case .genre:
            guard !selectedGenres.isEmpty else { return nil }
            return SmartPlaylistRule(kind: .genre, values: Array(selectedGenres))
        case .artist:
            guard !selectedArtists.isEmpty else { return nil }
            return SmartPlaylistRule(kind: .artist, values: Array(selectedArtists))
        case .decade:
            guard !selectedDecades.isEmpty else { return nil }
            return SmartPlaylistRule(kind: .decade, values: selectedDecades.map { "\($0)" })
        case .format:
            guard !selectedFormats.isEmpty else { return nil }
            return SmartPlaylistRule(kind: .fileFormat, values: Array(selectedFormats))
        case .explicitRating:
            guard !selectedExplicitChoices.isEmpty else { return nil }
            return SmartPlaylistRule(kind: .explicitRating, values: selectedExplicitChoices.map { "\($0.ratingValue)" })
        }
    }

    private var matchingSongs: [DeviceManager.ExportableSongInfo] {
        currentRule?.matchingSongs(in: songs) ?? []
    }

    private var suggestedName: String {
        switch ruleType {
        case .genre:
            return genreCounts.map(\.genre).filter(selectedGenres.contains).joined(separator: ", ")
        case .artist:
            return artistCounts.map(\.artist).filter(selectedArtists.contains).joined(separator: ", ")
        case .decade:
            return decadeCounts.map(\.decade).filter(selectedDecades.contains).map { "\($0)s" }.joined(separator: ", ")
        case .format:
            return formatCounts.map(\.format).filter(selectedFormats.contains).joined(separator: ", ")
        case .explicitRating:
            return ExplicitChoice.allCases.filter(selectedExplicitChoices.contains).map(\.rawValue).joined(separator: ", ")
        }
    }

    private var hasSelection: Bool {
        switch ruleType {
        case .genre: return !selectedGenres.isEmpty
        case .artist: return !selectedArtists.isEmpty
        case .decade: return !selectedDecades.isEmpty
        case .format: return !selectedFormats.isEmpty
        case .explicitRating: return !selectedExplicitChoices.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    ruleTypeSwitcher

                    if ruleType.usesSearch {
                        searchField
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            switch ruleType {
                            case .genre:
                                if filteredGenreCounts.isEmpty {
                                    emptyState(genreCounts.isEmpty ? "No genres found in your library." : "No genres match \"\(searchText)\".")
                                } else {
                                    ruleList(filteredGenreCounts.map { (title: $0.genre, count: $0.count, isSelected: selectedGenres.contains($0.genre), badge: nil) }, icon: ruleType.icon) { index in
                                        toggle(&selectedGenres, filteredGenreCounts[index].genre)
                                    }
                                }
                            case .artist:
                                if filteredArtistCounts.isEmpty {
                                    emptyState(artistCounts.isEmpty ? "No artists found in your library." : "No artists match \"\(searchText)\".")
                                } else {
                                    ruleList(filteredArtistCounts.map { (title: $0.artist, count: $0.count, isSelected: selectedArtists.contains($0.artist), badge: nil) }, icon: ruleType.icon) { index in
                                        toggle(&selectedArtists, filteredArtistCounts[index].artist)
                                    }
                                }
                            case .decade:
                                if decadeCounts.isEmpty {
                                    emptyState("No release years found in your library.")
                                } else {
                                    ruleList(decadeCounts.map { (title: "\($0.decade)s", count: $0.count, isSelected: selectedDecades.contains($0.decade), badge: nil) }, icon: ruleType.icon) { index in
                                        toggle(&selectedDecades, decadeCounts[index].decade)
                                    }
                                }
                            case .format:
                                if formatCounts.isEmpty {
                                    emptyState("No file formats found in your library.")
                                } else {
                                    ruleList(formatCounts.map { (title: $0.format, count: $0.count, isSelected: selectedFormats.contains($0.format), badge: Self.losslessFormats.contains($0.format) ? "LOSSLESS" : nil) }, icon: ruleType.icon) { index in
                                        toggle(&selectedFormats, formatCounts[index].format)
                                    }
                                }
                            case .explicitRating:
                                ruleList(ExplicitChoice.allCases.map { (title: $0.rawValue, count: explicitCounts[$0] ?? 0, isSelected: selectedExplicitChoices.contains($0), badge: nil) }, icon: ruleType.icon) { index in
                                    toggle(&selectedExplicitChoices, ExplicitChoice.allCases[index])
                                }
                            }
                        }
                        .background(panelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding()

                        if hasSelection {
                            Text("\(matchingSongs.count) song\(matchingSongs.count == 1 ? "" : "s") match \(hasMultipleSelections ? "any of these" : "this") — will be added to this playlist.")
                                .font(.footnote)
                                .foregroundStyle(mutedTextColor)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Smart Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onChange(of: ruleType) { _ in
                selectedGenres.removeAll()
                selectedArtists.removeAll()
                selectedDecades.removeAll()
                selectedFormats.removeAll()
                selectedExplicitChoices.removeAll()
                searchText = ""
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(accentPink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Next") {
                        guard let rule = currentRule, !matchingSongs.isEmpty else { return }
                        pendingRule = rule
                        pendingSongPids = matchingSongs.map(\.itemPid)
                        pendingSuggestedName = suggestedName
                        showingNaming = true
                    }
                    .foregroundStyle(accentPink)
                    .disabled(!hasSelection || matchingSongs.isEmpty)
                }
            }
            .sheet(isPresented: $showingNaming) {
                PlaylistNamingView(title: "Name Smart Playlist", icon: "wand.and.stars", iconTint: accentPink, initialName: pendingSuggestedName) { name, coverImageData in
                    guard !name.isEmpty, let rule = pendingRule else { return }
                    onCreate(name, pendingSongPids, rule, coverImageData)
                    dismiss()
                }
            }
        }
    }

    @State private var showingNaming = false
    @State private var pendingRule: SmartPlaylistRule?
    @State private var pendingSongPids: [Int64] = []
    @State private var pendingSuggestedName = ""

    private var hasMultipleSelections: Bool {
        switch ruleType {
        case .genre: return selectedGenres.count > 1
        case .artist: return selectedArtists.count > 1
        case .decade: return selectedDecades.count > 1
        case .format: return selectedFormats.count > 1
        case .explicitRating: return selectedExplicitChoices.count > 1
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private var ruleTypeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(RuleType.allCases) { type in
                Button {
                    ruleType = type
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: type.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ruleType == type ? accentPink : mutedTextColor)
                        Text(type.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ruleType == type ? strongTextColor : mutedTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Rectangle()
                            .fill(ruleType == type ? accentPink : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(mutedTextColor)
            TextField(ruleType == .genre ? "Search genres" : "Search artists", text: $searchText)
                .foregroundStyle(strongTextColor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(mutedTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(controlFillColor))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(mutedTextColor)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
    }

    private func ruleList(_ rows: [(title: String, count: Int, isSelected: Bool, badge: String?)], icon: String, onSelect: @escaping (Int) -> Void) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            Button {
                onSelect(index)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(controlFillColor)
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(mutedTextColor)
                    }

                    Text(row.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)

                    if let badge = row.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }

                    Spacer()

                    Text("\(row.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(mutedTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(controlFillColor))

                    if row.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accentPink)
                    } else {
                        Circle()
                            .stroke(mutedTextColor, lineWidth: 1)
                            .frame(width: 22, height: 22)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if index < rows.count - 1 {
                Divider().background(hairlineColor).padding(.leading, 66)
            }
        }
    }

}
