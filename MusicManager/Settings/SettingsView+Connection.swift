import SwiftUI
import UniformTypeIdentifiers

// MARK: - Connection
extension SettingsView {
    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONNECTION")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {

                Button {
                    showingPairingPicker = true
                } label: {
                    HStack {
                        Image(systemName: "link")
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.expectedPairingFileTitle)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(manager.connectionStatus)
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

                Divider().padding(.leading, 56)

                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 28)

                    Text("Status")
                        .font(.body)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.heartbeatReady ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(manager.connectionStatus)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button {
                            manager.startHeartbeat(forceReconnect: true)
                        } label: {
                            Text("Refresh")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        .padding(.leading, 8)
                        .disabled(!manager.hasValidExpectedPairingFile)
                        .opacity(manager.hasValidExpectedPairingFile ? 1 : 0.55)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }

    var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHORTCUTS")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                Link(destination: URL(string: "https://www.icloud.com/shortcuts/49de36f87bf44b21a38056d3c33e41fe")!) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .font(.body)
                            .foregroundColor(.purple)
                            .frame(width: 28)

                        Text("Add ByeTunes Shortcut")
                            .font(.body)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Color(.systemGray3))
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
    }
}
