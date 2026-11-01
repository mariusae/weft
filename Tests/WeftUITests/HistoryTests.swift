import Foundation
import ReflectCore
import Testing
@testable import WeftUI

/// A page's past and pages deleted, read from the graph's history.
@MainActor struct HistoryTests {
    private func git(_ arguments: String..., in root: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    @Test func aPagesVersionsAndThePagesDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("weft-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        git("init", "-q", in: root)
        let page = root.appendingPathComponent("notes/alpha.md")
        try "# Alpha\n\nFirst.\n".write(to: page, atomically: true, encoding: .utf8)
        try "# Beta\n\nGone soon.\n".write(to: root.appendingPathComponent("notes/beta.md"), atomically: true, encoding: .utf8)
        git("add", "-A", in: root); git("commit", "-qm", "one", in: root)
        try "# Alpha\n\nSecond.\n".write(to: page, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/beta.md"))
        git("add", "-A", in: root); git("commit", "-qm", "two", in: root)

        let backend = try #require(CommandLineGit.open(root))
        let versions = GraphHistory.versions(of: "notes/alpha.md", in: backend)
        #expect(versions.map(\.message) == ["two", "one"])
        #expect(versions.last?.body.contains("First.") == true)
        let deleted = GraphHistory.deleted(in: backend, root: root)
        #expect(deleted.map(\.path) == ["notes/beta.md"])
        #expect(deleted.first?.title == "Beta")
    }
}
