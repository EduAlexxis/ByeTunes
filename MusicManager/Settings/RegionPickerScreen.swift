import SwiftUI
import UniformTypeIdentifiers

struct RegionPickerScreen: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var currentOption: MetadataStoreRegionOption {
        MetadataStoreRegionOption(rawValue: selection)
    }

    private var groupedSections: [(letter: String, options: [MetadataStoreRegionOption])] {
        let all = MetadataStoreRegionOption.allCases
        let filtered = searchText.isEmpty ? all : all.filter {
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
        let grouped = Dictionary(grouping: filtered) { option in
            String(option.description.prefix(1)).uppercased()
        }
        return grouped.keys.sorted().compactMap { letter in
            guard let options = grouped[letter] else { return nil }
            return (letter, options.sorted { $0.description < $1.description })
        }
    }

    var body: some View {
        List {
            Section {
                row(for: currentOption)
            } header: {
                Text("Current Region")
            } footer: {
                Text("Choose which country's storefront to query when looking up metadata. Some songs or metadata details are only available in certain storefronts.")
            }

            ForEach(groupedSections, id: \.letter) { section in
                Section {
                    ForEach(section.options) { option in
                        row(for: option)
                    }
                } header: {
                    Text(section.letter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
        .navigationTitle("Store Region")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for option: MetadataStoreRegionOption) -> some View {
        let isSelected = option.rawValue == selection
        return Button {
            selection = option.rawValue
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(Self.flagEmoji(for: option.rawValue))
                    .font(.title2)
                Text(option.description)
                    .foregroundColor(.primary)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private static func flagEmoji(for regionCode: String) -> String {
        let regionalIndicatorBase: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for scalar in regionCode.uppercased().unicodeScalars {
            guard let flagScalar = Unicode.Scalar(regionalIndicatorBase + scalar.value) else { continue }
            scalars.append(flagScalar)
        }
        return scalars.isEmpty ? "🏳️" : String(scalars)
    }
}
