import SwiftUI

struct SongRowView: View {
    let song: SongMetadata
    var showEditButton: Bool = false
    var onEdit: () -> Void = {}
    var onSave: (() -> Void)? = nil
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            
            if let artworkData = (song.artworkPreviewData ?? song.artworkData), let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundColor(Color(.systemGray3))
                    )
            }
            
            
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                
                HStack {
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if song.explicitRating == 1 {
                        Text("E")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    
                    if song.richAppleMetadataFetched {
                        Image(systemName: "applelogo")
                            .font(.system(size: 10))
                            .foregroundColor(Color.accentColor)
                    }

                    Text(song.audioFormatLabel)
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(song.isLosslessAudio ? Color.purple : Color(.systemGray4))
                        .foregroundColor(song.isLosslessAudio ? .white : Color(.systemGray))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    
                    if let lyrics = song.lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                    }
                }
            }
            
            Spacer()
            
            
            if showEditButton {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            if let onSave {
                Button {
                    onSave()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color(.systemGray2))
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
