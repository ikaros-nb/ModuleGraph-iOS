import Foundation
import Testing
@testable import ModuleGraphCore

/// Scans `SampleApp/` at the repository root and compares the result with its committed `graph.json`.
/// See `SampleApp/README.md` to regenerate it.
@Suite struct SampleProjectTests {
    static let sample = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SampleApp")

    @Test func scanMatchesCommittedGraph() async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expected = try decoder.decode(Graph.self, from: try Data(contentsOf: Self.sample.appendingPathComponent("graph.json")))
        let graph = await ModuleGraphCore.Scanner.scan(root: Self.sample, options: .init(includeTests: true), now: expected.generatedAt)
        #expect(graph.nodes == expected.nodes)
        #expect(graph.edges == expected.edges)
        #expect(graph.warnings == expected.warnings)
    }
}
