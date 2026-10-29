import Foundation
import Testing
@testable import ModuleGraphCore

/// `Graph.swift` restates `schema/graph.schema.json` by hand: catch the two drifting apart.
@Suite struct SchemaTests {
    static let schema = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("schema/graph.schema.json")

    func kinds(_ list: String) throws -> [String] {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Self.schema)) as? [String: Any])
        let properties = json["properties"] as? [String: Any]
        let items = (properties?[list] as? [String: Any])?["items"] as? [String: Any]
        let kind = (items?["properties"] as? [String: Any])?["kind"] as? [String: Any]
        return try #require(kind?["enum"] as? [String])
    }

    @Test func nodeKindsMatch() throws {
        #expect(try kinds("nodes") == Node.Kind.allCases.map(\.rawValue))
    }

    @Test func edgeKindsMatch() throws {
        #expect(try kinds("edges") == Edge.Kind.allCases.map(\.rawValue))
    }
}
