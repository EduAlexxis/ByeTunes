import SwiftUI
import PhotosUI

struct PlaylistNamingView: View {
    let title: String
    let icon: String
    let iconTint: Color
    var initialName: String = ""
    let onConfirm: (String, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var coverImageData: Data?
    @FocusState private var isFocused: Bool

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color.white
    }

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.55)
    }

    private var placeholderBackground: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.95)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                VStack(spacing: 28) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(placeholderBackground)
                            .frame(width: 180, height: 180)
                            .overlay {
                                if let coverImageData, let uiImage = UIImage(data: coverImageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    Circle()
                                        .fill(iconTint)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Image(systemName: icon)
                                                .font(.system(size: 26, weight: .semibold))
                                                .foregroundStyle(.white)
                                        )
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .overlay(Circle().stroke(pageBackground, lineWidth: 2))
                                    .padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 40)

                    VStack(spacing: 8) {
                        TextField("Playlist Title", text: $name)
                            .focused($isFocused)
                            .multilineTextAlignment(.center)
                            .font(.title3)
                            .foregroundStyle(strongTextColor)

                        Rectangle()
                            .fill(mutedTextColor.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(strongTextColor)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(placeholderBackground))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onConfirm(trimmedName, coverImageData)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(trimmedName.isEmpty ? mutedTextColor : .white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(trimmedName.isEmpty ? placeholderBackground : Color.accentColor))
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                name = initialName
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isFocused = true
                }
            }
            .onChange(of: pickerItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let cropped = Self.squareCroppedJPEGData(from: data) {
                        await MainActor.run {
                            coverImageData = cropped
                        }
                    }
                }
            }
        }
    }

    private static func squareCroppedJPEGData(from data: Data, maxDimension: CGFloat = 1024) -> Data? {
        guard let original = UIImage(data: data) else { return nil }

        let normalized: UIImage
        if original.imageOrientation == .up {
            normalized = original
        } else {
            let renderer = UIGraphicsImageRenderer(size: original.size)
            normalized = renderer.image { _ in
                original.draw(in: CGRect(origin: .zero, size: original.size))
            }
        }

        guard let cgImage = normalized.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        let cropRect = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        var squareImage = UIImage(cgImage: croppedCGImage)
        if side > maxDimension {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxDimension, height: maxDimension))
            squareImage = renderer.image { _ in
                squareImage.draw(in: CGRect(x: 0, y: 0, width: maxDimension, height: maxDimension))
            }
        }

        return squareImage.jpegData(compressionQuality: 0.85)
    }
}
