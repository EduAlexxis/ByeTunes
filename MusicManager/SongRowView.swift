import SwiftUI

struct SongRowView: View {
    let song: SongMetadata
    var showEditButton: Bool = false
    var onEdit: () -> Void = {}
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Artwork
            if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
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
            
            // Title and Artist
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Edit button (Manual Match)
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
            
            // Delete button
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
