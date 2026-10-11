import SwiftUI

struct ServerStatusBanner: View {
    let status: ResolvedServerStatus
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    private var tint: Color {
        ServerStatusStore.color(named: status.colorName)
    }

    private var etaText: String? {
        guard let eta = status.eta, eta > Date() else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(eta) ? .none : .medium
        formatter.timeStyle = .short
        return "\(status.etaLabel) \(formatter.string(from: eta))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.icon)
                .font(.title3)
                .foregroundColor(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                if !status.title.isEmpty {
                    Text(status.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                }
                if !status.message.isEmpty {
                    Text(status.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let etaText {
                    Text(etaText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                if let buttonTitle = status.buttonTitle, let url = status.buttonURL {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 4) {
                            Text(buttonTitle)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            if status.dismissible {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(.systemGray3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
    }
}
