import SwiftUI

struct PlaylistDescriptionSheet: View {
    @Binding var text: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.white
    }

    private var accentPink: Color { Color(red: 1.0, green: 0.27, blue: 0.42) }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 160)
                        .background(panelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Shown under the playlist name in Music.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(accentPink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(accentPink)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
