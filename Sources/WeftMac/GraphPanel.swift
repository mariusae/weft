import AppKit
import WeftUI

/// Choosing a graph on the Mac: a folder.
@MainActor
enum GraphPanel {
    static func choose(for store: WikiStore) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Graph"
        panel.message = "Choose a Reflect graph: the folder holding daily/, notes/ and, once weft has written, wiki/."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.open(graph: url)
    }
}
