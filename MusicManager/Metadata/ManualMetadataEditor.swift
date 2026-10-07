import SwiftUI
import PhotosUI

struct ManualMetadataEditor: View {
    @Binding var song: SongMetadata
    @Binding var isPresented: Bool
    var onSave: ((SongMetadata) -> Void)? = nil
    
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""
    @State private var trackNumber: String = ""
    @State private var lyrics: String = ""
    @State private var explicitRating: Int = 0

    @State private var useCustomAlbumColor: Bool = false
    @State private var customAlbumColor: Color = .black

    @State private var artworkItem: PhotosPickerItem?
    @State private var originalArtworkData: Data?
    @State private var artworkData: Data?
    @State private var pendingArtworkData: Data?
    @State private var showingArtworkCropper = false

    @State private var showingSearchSheet = false
    @State private var showingLyricsSearchSheet = false

    @AppStorage("metadataSource") private var metadataSource = "apple"

    @FocusState private var focusedField: Field?

    enum Field {
        case title, artist, album, genre, year, trackNumber
    }

    // MARK: - Color helpers
    private static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(r * 255)
        let gi = Int(g * 255)
        let bi = Int(b * 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    private static func color(fromHex hex: String) -> Color? {
        let normalized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if let data = artworkData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 140, height: 140)
                                    .cornerRadius(12)
                                    .shadow(radius: 4)
                            } else {
                                ZStack {
                                    Color(uiColor: .systemGray5)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 140, height: 140)
                                .cornerRadius(12)
                            }
                            
                            PhotosPicker(selection: $artworkItem, matching: .images) {
                                Label("Change Artwork", systemImage: "photo.on.rectangle")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Artwork")
                }
                
                Section {
                    Button {
                        showingSearchSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.accentColor)
                            Text("Search Metadata")
                                .foregroundColor(.accentColor)
                            
                            Spacer()
                            
                            Text(metadataSource == "local" ? "iTunes" : (metadataSource == "apple" ? "Apple Music" : metadataSource.capitalized))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(uiColor: .tertiaryLabel))
                        }
                    }
                } footer: {
                    Text("Search \(metadataSource == "local" ? "iTunes" : (metadataSource == "apple" ? "Apple Music" : metadataSource.capitalized)) to auto-fill metadata fields")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Title")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter title", text: $title)
                            .focused($focusedField, equals: .title)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Artist")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter artist", text: $artist)
                            .focused($focusedField, equals: .artist)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Album")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter album", text: $album)
                            .focused($focusedField, equals: .album)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Genre")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter genre", text: $genre)
                            .focused($focusedField, equals: .genre)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Year")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("YYYY", text: $year)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .year)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Track Number")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Track #", text: $trackNumber)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .trackNumber)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Content Rating")
                        Spacer()
                        Picker("", selection: $explicitRating) {
                            Text("None").tag(0)
                            Text("Explicit").tag(1)
                            Text("Clean").tag(2)
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                    }
                    .padding(.vertical, 4)

                    Toggle(isOn: $useCustomAlbumColor) {
                        HStack(spacing: 8) {
                            Image(systemName: "paintpalette.fill")
                                .foregroundStyle(.linearGradient(
                                    colors: [.purple, .pink, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Custom Album Color")
                                    .font(.body)
                                Text("Overrides background in Music app")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if useCustomAlbumColor {
                        HStack {
                            ColorPicker("Background Color", selection: $customAlbumColor, supportsOpacity: false)
                                .labelsHidden()
                            Spacer()
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(customAlbumColor)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                                    )
                                    .shadow(color: customAlbumColor.opacity(0.4), radius: 4, x: 0, y: 2)
                                Text("A")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(isLightColor(customAlbumColor) ? .black : .white)
                            }
                            Text(Self.hexString(from: customAlbumColor))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Details")
                }
                
                Section {
                    TextEditor(text: $lyrics)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    HStack {
                        Text("Lyrics")
                        Spacer()
                        if !lyrics.isEmpty {
                            Text("\(lyrics.components(separatedBy: .newlines).count) lines")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            showingLyricsSearchSheet = true
                        } label: {
                            Image(systemName: "text.magnifyingglass")
                        }
                        .disabled(title.isEmpty || artist.isEmpty)
                        .padding(.leading, 8)
                    }
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                loadFieldsFromSong()
            }
            .task(id: song.id) {
                await loadFullResolutionArtworkIfNeeded()
            }
            .onChange(of: artworkItem, perform: { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            self.pendingArtworkData = data
                            self.showingArtworkCropper = true
                        }
                    }
                }
            })
            .sheet(isPresented: $showingSearchSheet, onDismiss: {
                loadFieldsFromSong()
            }) {
                iTunesSearchSheet(song: $song, isPresented: $showingSearchSheet)
            }
            .sheet(isPresented: $showingLyricsSearchSheet) {
                LyricsSearchSheet(lyrics: $lyrics, isPresented: $showingLyricsSearchSheet, songTitle: title, songArtist: artist)
            }
            .sheet(isPresented: $showingArtworkCropper) {
                if let baseData = pendingArtworkData {
                    ArtworkCropEditor(imageData: baseData) { croppedData in
                        self.originalArtworkData = croppedData
                        self.artworkData = croppedData
                        self.pendingArtworkData = nil
                    }
                } else {
                    EmptyView()
                }
            }
            .onChange(of: showingArtworkCropper) { isShowing in
                if !isShowing {
                    pendingArtworkData = nil
                }
            }
        }
    }
    
    private func isLightColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        return luminance > 0.62
    }

    private func loadFieldsFromSong() {
        title = song.title
        artist = song.artist
        album = song.album
        genre = song.genre
        year = String(song.year)
        if let track = song.trackNumber {
            trackNumber = String(track)
        }
        lyrics = song.lyrics ?? ""
        let resolvedArtworkData = song.artworkData ?? song.artworkPreviewData
        artworkData = resolvedArtworkData
        originalArtworkData = resolvedArtworkData
        pendingArtworkData = nil
        explicitRating = max(0, song.explicitRating)
        if let hex = song.customAlbumBackgroundColor,
           let color = Self.color(fromHex: hex) {
            useCustomAlbumColor = true
            customAlbumColor = color
        } else {
            useCustomAlbumColor = false
            customAlbumColor = .black
        }
    }

    @MainActor
    private func applyResolvedArtwork(_ data: Data) {
        artworkData = data
        originalArtworkData = data
        song.artworkData = data
    }

    private func loadFullResolutionArtworkIfNeeded() async {
        guard song.artworkData == nil, song.artworkPreviewData != nil else { return }
        guard let fullArtworkData = await SongMetadata.extractEmbeddedArtwork(from: song.localURL) else { return }
        await MainActor.run {
            applyResolvedArtwork(fullArtworkData)
        }
    }
    
    private func saveChanges() {
        var updatedSong = song
        updatedSong.title = title
        updatedSong.artist = artist
        updatedSong.album = album
        updatedSong.genre = genre
        let trimmedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedYear.isEmpty {
            updatedSong.year = 0
        } else if let y = Int(trimmedYear) {
            updatedSong.year = y
        }
        if let t = Int(trackNumber) {
            updatedSong.trackNumber = t
        } else {
            updatedSong.trackNumber = nil
        }
        updatedSong.lyrics = lyrics.isEmpty ? nil : lyrics
        updatedSong.artworkData = artworkData
        if let artworkData {
            updatedSong.artworkPreviewData = artworkData
        }
        updatedSong.explicitRating = explicitRating
        updatedSong.customAlbumBackgroundColor = useCustomAlbumColor ? Self.hexString(from: customAlbumColor) : nil

        song = updatedSong
        onSave?(updatedSong)
        isPresented = false
    }
    
}

private struct ArtworkCropEditor: View {
    let imageData: Data
    let onApply: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var cropViewportSide: CGFloat = 320
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width - 56, geo.size.height - 250)
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 18) {
                        Spacer(minLength: 12)

                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                .frame(width: side + 24, height: side + 24)

                            if let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .scaleEffect(min(max(scale, minScale), maxScale))
                                    .offset(offset)
                                    .frame(width: side, height: side)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                                    )
                                    .gesture(
                                        SimultaneousGesture(
                                            MagnificationGesture()
                                                .onChanged { value in
                                                    scale = min(max(lastScale * value, minScale), maxScale)
                                                }
                                                .onEnded { _ in
                                                    scale = min(max(scale, minScale), maxScale)
                                                    lastScale = scale
                                                    offset = clampedOffset(
                                                        offset,
                                                        imageSize: uiImage.size,
                                                        viewport: side,
                                                        scale: scale
                                                    )
                                                    lastOffset = offset
                                                },
                                            DragGesture()
                                                .onChanged { value in
                                                    let raw = CGSize(
                                                        width: lastOffset.width + value.translation.width,
                                                        height: lastOffset.height + value.translation.height
                                                    )
                                                    offset = clampedOffset(
                                                        raw,
                                                        imageSize: uiImage.size,
                                                        viewport: side,
                                                        scale: scale
                                                    )
                                                }
                                                .onEnded { _ in
                                                    offset = clampedOffset(
                                                        offset,
                                                        imageSize: uiImage.size,
                                                        viewport: side,
                                                        scale: max(scale, minScale)
                                                    )
                                                    lastOffset = offset
                                                }
                                        )
                                    )
                                    .onAppear {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                            }
                        }
                        .frame(width: side + 24, height: side + 24)

                        Text("Pinch to zoom and drag to position")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button("Reset") {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                        .font(.subheadline.weight(.semibold))

                        Spacer()
                    }
                    .padding(.horizontal, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    cropViewportSide = side
                }
                .onChange(of: side) { newValue in
                    cropViewportSide = newValue
                }
            }
            .navigationTitle("Edit Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let cropped = cropToSquare(
                            imageData: imageData,
                            scale: scale,
                            offset: offset,
                            viewportSide: cropViewportSide,
                            outputSide: 1200
                        ) {
                            onApply(cropped)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func clampedOffset(_ value: CGSize, imageSize: CGSize, viewport: CGFloat, scale: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fillScale = max(viewport / imageSize.width, viewport / imageSize.height)
        let displayW = imageSize.width * fillScale * scale
        let displayH = imageSize.height * fillScale * scale
        let maxX = max(0, (displayW - viewport) / 2)
        let maxY = max(0, (displayH - viewport) / 2)
        
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }
    
    private func cropToSquare(imageData: Data, scale: CGFloat, offset: CGSize, viewportSide: CGFloat, outputSide: CGFloat) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return imageData }
        
        let viewport = max(1, viewportSide)
        let fillScale = max(viewport / imgSize.width, viewport / imgSize.height)
        let drawW = imgSize.width * fillScale * scale
        let drawH = imgSize.height * fillScale * scale
        
        let drawRect = CGRect(
            x: (viewport - drawW) / 2 + offset.width,
            y: (viewport - drawH) / 2 + offset.height,
            width: drawW,
            height: drawH
        )
        
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
        
        let rendered = renderer.image { _ in
            let transform = CGAffineTransform(scaleX: outputSide / viewport, y: outputSide / viewport)
            image.draw(in: drawRect.applying(transform))
        }
        
        return rendered.jpegData(compressionQuality: 0.95) ?? rendered.pngData()
    }
}
