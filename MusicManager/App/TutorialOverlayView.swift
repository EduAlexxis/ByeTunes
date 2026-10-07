import SwiftUI

// MARK: - Tutorial Overlay
struct TutorialOverlayView: View {

    @Binding var isComplete: Bool
    @Binding var songs: [SongMetadata]
    @Binding var selectedTab: Int
    let downloadTabIndex: Int

    private enum Step {
        case metadataChoice
        case downloadHint
        case injectHint
    }

    @State private var step: Step = .metadataChoice

    @AppStorage("appleRichMetadata") private var appleRichMetadata = true
    @AppStorage("autofetchMetadata") private var autofetchMetadata  = true
    @AppStorage("fetchLyrics")       private var fetchLyrics        = false
    @AppStorage("metadataSource")    private var metadataSource     = "apple"

    var body: some View {
        ZStack(alignment: .bottom) {
            switch step {
            case .metadataChoice:
                metadataScreen
                    .transition(.opacity)
            case .downloadHint:
                hintSheet(
                    progress: 0,
                    icon: "arrow.down.circle.fill",
                    title: "Download your first song",
                    body: "Open the Download tab, search for any song, and tap the download button next to it.",
                    tabIcon: "arrow.down.circle",
                    tabLabel: "Download tab",
                    doneLabel: nil
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onChange(of: songs.count, perform: { count in
                    if count > 0 {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            step = .injectHint
                            selectedTab = 0
                        }
                    }
                })
            case .injectHint:
                hintSheet(
                    progress: 1,
                    icon: "iphone.and.arrow.forward",
                    title: "Send it to your iPhone",
                    body: "Your song is in the queue. Tap Inject in the Music tab to push it into your Music library.",
                    tabIcon: "music.note",
                    tabLabel: "Music tab",
                    doneLabel: "Done"
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onChange(of: songs.count, perform: { count in
                    if count == 0 {
                        finish()
                    }
                })
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)
    }

    // MARK: - Metadata Choice
    @ViewBuilder
    private var metadataScreen: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: "music.note")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }

                    Text("How do you want\nyour music?")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("Controls how ByeTunes handles metadata.\nChangeable anytime in Settings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    metadataOptionCard(
                        icon: "sparkles",
                        title: "Apple Music Style",
                        badge: "Recommended",
                        points: [
                            "Artwork fetched from Apple Music",
                            "Lyrics pulled automatically",
                            "Atmos and lossless quality matched"
                        ],
                        isRecommended: true,
                        action: {
                            appleRichMetadata = true
                            autofetchMetadata = true
                            fetchLyrics       = true
                            metadataSource    = "apple"
                            proceed()
                        }
                    )

                    metadataOptionCard(
                        icon: "slider.horizontal.3",
                        title: "Custom",
                        badge: "Advanced",
                        points: [
                            "You control every setting",
                            "Pick your own metadata sources",
                            "Configure it all in Settings"
                        ],
                        isRecommended: false,
                        action: { proceed() }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                Button("Skip tutorial") { finish() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.18), radius: 32, x: 0, y: 16)
            )
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func metadataOptionCard(
        icon: String,
        title: String,
        badge: String,
        points: [String],
        isRecommended: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(isRecommended ? 0.14 : 0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isRecommended ? .accentColor : Color(.systemGray))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isRecommended ? .accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isRecommended ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
                            )
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.systemGray3))
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(points, id: \.self) { point in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isRecommended ? .accentColor : Color(.systemGray))
                            Text(point)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(CardPressStyle())
    }

    // MARK: - Hint Sheet
    @ViewBuilder
    private func hintSheet(
        progress: Int,
        icon: String,
        title: String,
        body: String,
        tabIcon: String,
        tabLabel: String,
        doneLabel: String?
    ) -> some View {
        VStack(spacing: 0) {
            Spacer().allowsHitTesting(false)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                VStack(spacing: 18) {
                    HStack {
                        HStack(spacing: 6) {
                            ForEach(0..<2) { i in
                                Capsule()
                                    .fill(i == progress ? Color.accentColor : Color(.systemGray5))
                                    .frame(width: i == progress ? 20 : 8, height: 7)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
                            }
                        }
                        Spacer()
                        Button("Skip") { finish() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentColor.opacity(0.10))
                                .frame(width: 50, height: 50)
                            Image(systemName: icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.system(size: 17, weight: .bold))
                            Text(body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: tabIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text(tabLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.accentColor)
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.accentColor.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(0.10))
                        )

                        Spacer()

                        if let doneLabel {
                            Button(action: finish) {
                                Text(doneLabel)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.accentColor)
                                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 38)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.09), radius: 24, x: 0, y: -6)
            .padding(.horizontal, 10)
            .padding(.bottom, 92)
        }
    }

    // MARK: - Helpers
    private func proceed() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            step = .downloadHint
            selectedTab = downloadTabIndex
        }
    }

    private func finish() {
        withAnimation { isComplete = true }
    }
}

// MARK: - Card Press Style
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
