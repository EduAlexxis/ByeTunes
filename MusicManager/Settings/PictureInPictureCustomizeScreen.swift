import SwiftUI
import UIKit
import PhotosUI

struct PictureInPictureCustomizeScreen: View {
    @AppStorage(PictureInPictureStyle.Key.theme) private var themeRaw = PictureInPictureTheme.system.rawValue
    @AppStorage(PictureInPictureStyle.Key.background) private var backgroundHex = PictureInPictureStyle.Default.background
    @AppStorage(PictureInPictureStyle.Key.backgroundEnd) private var backgroundEndHex = PictureInPictureStyle.Default.backgroundEnd
    @AppStorage(PictureInPictureStyle.Key.gradient) private var useGradient = false
    @AppStorage(PictureInPictureStyle.Key.card) private var cardHex = PictureInPictureStyle.Default.card
    @AppStorage(PictureInPictureStyle.Key.text) private var textHex = PictureInPictureStyle.Default.text
    @AppStorage(PictureInPictureStyle.Key.accent) private var accentHex = PictureInPictureStyle.Default.accent
    @AppStorage(PictureInPictureStyle.Key.nextUpCount) private var nextUpCount = 1
    @AppStorage(PictureInPictureStyle.Key.showArtwork) private var showArtwork = true
    @AppStorage(PictureInPictureStyle.Key.showSpeed) private var showSpeed = true
    @AppStorage(PictureInPictureStyle.Key.showCounter) private var showCounter = true
    @AppStorage(PictureInPictureStyle.Key.useBackgroundImage) private var useBackgroundImage = false
    @AppStorage(PictureInPictureStyle.Key.backgroundImageVersion) private var backgroundImageVersion = ""
    @AppStorage(PictureInPictureStyle.Key.backgroundDim) private var backgroundDim = 0.35

    @State private var pickerItem: PhotosPickerItem?

    @State private var previewRenderer = PictureInPictureRenderer()

    private var theme: PictureInPictureTheme {
        PictureInPictureTheme(rawValue: themeRaw) ?? .system
    }

    private var style: PictureInPictureStyle {
        var style = PictureInPictureStyle()
        style.theme = theme
        style.customBackground = UIColor(hex: backgroundHex) ?? style.customBackground
        style.customBackgroundEnd = UIColor(hex: backgroundEndHex) ?? style.customBackgroundEnd
        style.customGradient = useGradient
        style.customCard = UIColor(hex: cardHex) ?? style.customCard
        style.customText = UIColor(hex: textHex) ?? style.customText
        style.customAccent = UIColor(hex: accentHex) ?? style.customAccent
        style.nextUpCount = nextUpCount
        style.showArtwork = showArtwork
        style.showSpeed = showSpeed
        style.showCounter = showCounter
        style.useBackgroundImage = useBackgroundImage
        style.backgroundImageVersion = backgroundImageVersion
        style.backgroundDim = backgroundDim
        return style
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    previewSection
                    themeSection
                    pictureSection
                    if theme == .custom {
                        colorsSection
                    }
                    displaySection
                    resetSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Customize Picture in Picture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PREVIEW")

            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                VStack(spacing: 0) {
                    if let image = previewRenderer.previewImage(style: style, time: timeline.date.timeIntervalSinceReferenceDate) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                            .accessibilityLabel("Preview of the Picture in Picture window")
                    }
                }
                .modifier(SettingsCardStyle())
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("THEME")

            VStack(spacing: 0) {
                HStack {
                    rowIcon("paintpalette")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Theme")
                            .font(.body)
                        Text("Match App follows light and dark mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Picker("Theme", selection: $themeRaw) {
                        ForEach(PictureInPictureTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
            .modifier(SettingsCardStyle())
        }
    }

    private var pictureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("BACKGROUND PICTURE")

            VStack(spacing: 0) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack {
                        rowIcon("photo.on.rectangle")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(backgroundImageVersion.isEmpty ? "Choose Picture" : "Change Picture")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Use your own image behind the rows.")
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

                if !backgroundImageVersion.isEmpty {
                    Divider().padding(.leading, 56)

                    toggleRow(icon: "photo", title: "Use Picture", subtitle: "Show it as the background.", isOn: $useBackgroundImage)

                    if useBackgroundImage {
                        Divider().padding(.leading, 56)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                rowIcon("circle.lefthalf.filled.righthalf.striped.horizontal")

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dim Picture")
                                        .font(.body)
                                    Text("Darken it so the text stays easy to read.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(Int((backgroundDim * 100).rounded()))%")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(value: $backgroundDim, in: 0...0.8)
                                .tint(.accentColor)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                    }

                    Divider().padding(.leading, 56)

                    Button {
                        PictureInPictureBackgroundStore.remove()
                        backgroundImageVersion = ""
                        useBackgroundImage = false
                    } label: {
                        HStack {
                            rowIcon("trash", color: .red)

                            Text("Remove Picture")
                                .font(.body)
                                .foregroundColor(.red)

                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .modifier(SettingsCardStyle())
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let version = PictureInPictureBackgroundStore.save(image) {
                        backgroundImageVersion = version
                        useBackgroundImage = true
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("COLORS")

            VStack(spacing: 0) {
                colorRow(icon: "rectangle.fill", title: "Background", subtitle: "Behind the rows.", hex: $backgroundHex, fallback: PictureInPictureStyle.Default.background)

                Divider().padding(.leading, 56)

                toggleRow(icon: "circle.lefthalf.filled", title: "Gradient Background", subtitle: "Blend into a second color.", isOn: $useGradient)

                if useGradient {
                    Divider().padding(.leading, 56)

                    colorRow(icon: "paintbrush.pointed", title: "Gradient End", subtitle: "Color at the bottom.", hex: $backgroundEndHex, fallback: PictureInPictureStyle.Default.backgroundEnd)
                }

                Divider().padding(.leading, 56)

                colorRow(icon: "rectangle.stack", title: "Rows", subtitle: "Song row background.", hex: $cardHex, fallback: PictureInPictureStyle.Default.card)

                Divider().padding(.leading, 56)

                colorRow(icon: "textformat", title: "Text", subtitle: "Titles and artists.", hex: $textHex, fallback: PictureInPictureStyle.Default.text)

                Divider().padding(.leading, 56)

                colorRow(icon: "slider.horizontal.below.rectangle", title: "Progress Bar", subtitle: "Download progress color.", hex: $accentHex, fallback: PictureInPictureStyle.Default.accent)
            }
            .modifier(SettingsCardStyle())
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DISPLAY")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        rowIcon("list.bullet.rectangle")

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Up Rows")
                                .font(.body)
                            Text("Songs waiting after the current one.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    Picker("Next Up Rows", selection: $nextUpCount) {
                        Text("Off").tag(0)
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 56)

                toggleRow(icon: "number", title: "Show Counter", subtitle: "The \"3 of 12\" header.", isOn: $showCounter)

                Divider().padding(.leading, 56)

                toggleRow(icon: "photo", title: "Show Artwork", subtitle: "Album covers on each row.", isOn: $showArtwork)

                Divider().padding(.leading, 56)

                toggleRow(icon: "speedometer", title: "Show Speed", subtitle: "Download speed per song.", isOn: $showSpeed)
            }
            .modifier(SettingsCardStyle())

            Text("Showing fewer rows makes the window smaller. You can also pinch the window to resize it while it is open.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var resetSection: some View {
        VStack(spacing: 0) {
            Button {
                themeRaw = PictureInPictureTheme.system.rawValue
                backgroundHex = PictureInPictureStyle.Default.background
                backgroundEndHex = PictureInPictureStyle.Default.backgroundEnd
                useGradient = false
                cardHex = PictureInPictureStyle.Default.card
                textHex = PictureInPictureStyle.Default.text
                accentHex = PictureInPictureStyle.Default.accent
                nextUpCount = 1
                showArtwork = true
                showSpeed = true
                showCounter = true
                PictureInPictureBackgroundStore.remove()
                backgroundImageVersion = ""
                useBackgroundImage = false
                backgroundDim = 0.35
            } label: {
                HStack {
                    rowIcon("arrow.counterclockwise", color: .red)

                    Text("Reset to Defaults")
                        .font(.body)
                        .foregroundColor(.red)

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
        .modifier(SettingsCardStyle())
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    private func rowIcon(_ name: String, color: Color = .primary) -> some View {
        Image(systemName: name)
            .font(.body)
            .foregroundColor(color)
            .frame(width: 28)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                rowIcon(icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private func colorRow(icon: String, title: String, subtitle: String, hex: Binding<String>, fallback: String) -> some View {
        HStack {
            rowIcon(icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            ColorPicker(title, selection: colorBinding(hex, fallback: fallback), supportsOpacity: false)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private func colorBinding(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding<Color>(
            get: { Color(UIColor(hex: hex.wrappedValue) ?? UIColor(hex: fallback) ?? .black) },
            set: { hex.wrappedValue = UIColor($0).hexString }
        )
    }
}

private struct SettingsCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
    }
}
