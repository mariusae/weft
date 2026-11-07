import GraphKit
import ReflectCore
import SwiftUI

/// The icons to choose among, by group, each by its name — found by
/// typing one — and None. A page's, or a river's.
struct IconPicker: View {
    /// The symbol chosen now, if any.
    let current: String?
    /// What the icons are drawn in.
    var tint: Color = Ink.secondary.color
    /// What the chosen one is filled with.
    var chosenFill: Color = Ink.accent.color
    /// Whether None is offered.
    var allowsNone = true
    let choose: (String?) -> Void
    @State private var search = ""

    private var groups: [PageIcon.Group] {
        let words = search.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return PageIcon.groups }
        return PageIcon.groups.compactMap { group in
            let found = group.choices.filter {
                $0.name.localizedCaseInsensitiveContains(words) || $0.symbol.localizedCaseInsensitiveContains(words)
                    || group.name.localizedCaseInsensitiveContains(words)
            }
            return found.isEmpty ? nil : PageIcon.Group(name: group.name, choices: found)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search Icons", text: $search)
                    .textFieldStyle(.roundedBorder)
                if allowsNone {
                    Button("None") { choose(nil) }
                        .disabled(current == nil)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.secondary.color)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                                ForEach(group.choices) { choice in
                                    IconCell(choice: choice, chosen: choice.symbol == current, tint: tint, fill: chosenFill) { choose(choice.symbol) }
                                }
                            }
                        }
                    }
                    if groups.isEmpty {
                        Text("No icon called “\(search)”")
                            .foregroundStyle(Ink.secondary.color)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(14)
        .frame(width: 8 * 36 + 7 * 6 + 28, height: 380)
    }
}

private struct IconCell: View {
    let choice: PageIcon.Choice
    let chosen: Bool
    let tint: Color
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: choice.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(chosen ? .white : tint)
                .frame(width: 36, height: 36)
                .background(chosen ? fill : Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointing()
        .help(choice.name)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A saved river's icon, chosen in a sheet of its own: drawn in its colour.
struct RiverIconSheet: View {
    let name: String
    let current: String?
    let color: String?
    let choose: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let tint = color.map(RiverColor.color) ?? Ink.accent.color
            IconPicker(current: current, tint: tint, chosenFill: tint) { symbol in
                choose(symbol)
                dismiss()
            }
            .navigationTitle("Icon for “\(name)”")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
