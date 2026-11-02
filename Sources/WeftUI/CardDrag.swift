import SwiftUI
import UniformTypeIdentifiers

/// Cards dragged by their titles to another place in the river — on the
/// phone, held first. What is dragged is the card's title, as a type only
/// weft takes: dropped on a card's text, it writes nothing there.
extension UTType {
    static let weftCard = UTType(exportedAs: "com.mariusae.weft.card", conformingTo: .data)
}

/// Where a dragged card would go: just before or after another.
struct CardDrop: Equatable {
    let title: String
    let after: Bool
}

extension View {
    /// Dragged by this, the card `title` goes with the pointer, or the finger.
    func draggingCard(_ title: String, shown: String, enabled: Bool = true) -> some View {
        modifier(CardDragSource(title: title, shown: shown, enabled: enabled))
    }
}

private struct CardDragSource: ViewModifier {
    let title: String
    let shown: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onDrag {
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.weftCard.identifier, visibility: .ownProcess) { done in
                        done(Data(title.utf8), nil)
                        return nil
                    }
                    provider.suggestedName = shown
                    return provider
                } preview: {
                    Text(shown)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Ink.text.color)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 10))
                }
        } else {
            content
        }
    }
}

/// A card in the river that a dragged card can be dropped on: in its top
/// half, to go before it; in its bottom half, after — a line in the gap
/// saying which.
struct DroppableCard: View {
    @Environment(River.self) private var river
    let title: String
    @Binding var drop: CardDrop?
    /// The gap between cards, the line drawn in its middle.
    let gap: CGFloat
    @State private var height: CGFloat = 0

    var body: some View {
        Card(title: title)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(of: [.weftCard], delegate: CardDropDelegate(title: title, height: height, drop: $drop, river: river))
            .overlay(alignment: drop?.after == true ? .bottom : .top) {
                if let drop, drop.title == title {
                    Capsule()
                        .fill(Ink.accent.color)
                        .frame(height: 3)
                        .padding(.horizontal, 10)
                        .offset(y: (drop.after ? 1 : -1) * gap / 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct CardDropDelegate: DropDelegate {
    let title: String
    let height: CGFloat
    @Binding var drop: CardDrop?
    let river: River

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.weftCard]) }

    func dropEntered(info: DropInfo) { aim(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        aim(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if drop?.title == title { drop = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        drop = nil
        return river.moveDropped(info, to: CardDrop(title: title, after: info.location.y > height / 2))
    }

    private func aim(_ info: DropInfo) {
        let aimed = CardDrop(title: title, after: info.location.y > height / 2)
        if drop != aimed { drop = aimed }
    }
}

extension River {
    /// The card a drop carries, moved to where it was dropped.
    func moveDropped(_ info: DropInfo, to place: CardDrop) -> Bool {
        guard let provider = info.itemProviders(for: [.weftCard]).first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.weftCard.identifier) { [self] data, _ in
            guard let data, let dragged = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                withAnimation(.snappy(duration: 0.28)) { move(dragged, to: place.title, after: place.after) }
            }
        }
        return true
    }
}
