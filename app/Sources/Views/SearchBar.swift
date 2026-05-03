import MapKit
import SwiftUI

struct SearchBar: View {
    @Environment(AppViewModel.self) private var app
    @State private var search = PlaceSearchModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            if focused && !search.suggestions.isEmpty {
                suggestionsList
            }
        }
        .frame(maxWidth: 420)
        .onAppear { search.setRegion(app.lastKnownRegion) }
        .onChange(of: app.lastKnownRegion.center.latitude) { _, _ in
            search.setRegion(app.lastKnownRegion)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            if search.isResolving {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            TextField("Search places", text: Binding(
                get: { search.query },
                set: { search.updateQuery($0) }
            ))
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit {
                if let first = search.suggestions.first {
                    Task { await select(first) }
                }
            }
            if !search.query.isEmpty {
                Button {
                    search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 1)
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let items = Array(search.suggestions.prefix(8).enumerated())
            ForEach(items, id: \.offset) { index, suggestion in
                Button {
                    Task { await select(suggestion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).font(.body)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 2)
    }

    private func select(_ completion: MKLocalSearchCompletion) async {
        guard let coord = await search.resolve(completion) else { return }
        app.placeSelected(coord)
        search.clear()
        focused = false
    }
}
