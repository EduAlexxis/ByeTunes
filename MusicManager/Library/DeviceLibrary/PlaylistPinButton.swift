import SwiftUI

// MARK: - Pin Button
struct PlaylistPinButton: View {
    @ObservedObject var manager: DeviceManager
    let playlistPid: Int64
    @Binding var isSyncing: Bool
    let textColor: Color
    let fillColor: Color
    let strokeColor: Color
    let onToggle: (Bool) -> Void

    var body: some View {
        let isPinned = manager.pinnedPlaylistPids.contains(playlistPid)

        Button {
            onToggle(isPinned)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 14, weight: .semibold))
                Text(isPinned ? "Unpin" : "Pin")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Capsule()
                    .fill(fillColor)
                    .overlay(
                        Capsule()
                            .stroke(strokeColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isSyncing)
    }
}
