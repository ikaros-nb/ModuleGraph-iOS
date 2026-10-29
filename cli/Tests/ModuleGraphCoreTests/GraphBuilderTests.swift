import Foundation
import Testing
@testable import ModuleGraphCore

@Suite struct GraphBuilderTests {
    let root = URL(fileURLWithPath: "/tmp/Project")
    let now = Date(timeIntervalSince1970: 0)

    func manifest(_ json: String) throws -> PackageManifest { try PackageManifest.decode(Data(json.utf8)) }

    @Test func resolvesProductsToTargetsAndKeepsExternals() throws {
        let domain = try manifest("""
        { "name": "Domain", "dependencies": [ { "sourceControl": [ { "identity": "swift-collections" } ] } ],
          "products": [ { "name": "Domain", "targets": ["Domain"] }, { "name": "DomainMocks", "targets": ["DomainMocks"] } ],
          "targets": [
            { "name": "Domain", "type": "regular", "dependencies": [ { "product": ["Collections", "swift-collections", null, null] } ] },
            { "name": "DomainMocks", "type": "regular", "dependencies": [ { "byName": ["Domain", null] } ] },
            { "name": "DomainTests", "type": "test", "dependencies": [ { "target": ["Domain", null] } ] }
          ] }
        """)
        let app = XcodeProject(name: "App", directory: root, targets: [
            XcodeTarget(name: "App", kind: .app, packageProducts: ["DomainMocks"], sourcePaths: ["App"]),
        ])
        let builder = GraphBuilder(root: root, includeTests: false, scanImports: false)
        let graph = builder.build(
            packages: [DumpedPackage(directory: root.appendingPathComponent("Packages/Domain"), manifest: domain)],
            projects: [app], warnings: [], now: now
        )
        #expect(graph.nodes.map(\.id) == ["App", "Collections", "Domain", "DomainMocks"])
        #expect(graph.nodes.first { $0.id == "Collections" }?.kind == .external)
        #expect(graph.nodes.first { $0.id == "Domain" }?.group == "Packages")
        #expect(graph.nodes.first { $0.id == "Domain" }?.path == "Packages/Domain/Sources/Domain")
        #expect(graph.edges == [
            Edge(from: "App", to: "DomainMocks", kind: .declared),
            Edge(from: "Domain", to: "Collections", kind: .declared),
            Edge(from: "DomainMocks", to: "Domain", kind: .declared),
        ])
    }

    @Test func includesTestsOnRequest() throws {
        let toolkit = try manifest("""
        { "name": "Toolkit", "dependencies": [], "products": [],
          "targets": [ { "name": "Toolkit", "type": "regular", "dependencies": [] },
                       { "name": "ToolkitTests", "type": "test", "dependencies": [ { "byName": ["Toolkit", null] } ] } ] }
        """)
        let package = DumpedPackage(directory: root.appendingPathComponent("Packages/Toolkit"), manifest: toolkit)
        let with = GraphBuilder(root: root, includeTests: true, scanImports: false).build(packages: [package], projects: [], warnings: [], now: now)
        #expect(with.nodes.map(\.id) == ["Toolkit", "ToolkitTests"])
        #expect(with.nodes.last?.kind == .test)
        // The directory doesn't exist, and a package with one test target may keep its tests in Tests/ directly.
        #expect(with.nodes.last?.path == "Packages/Toolkit/Tests")
    }
}
