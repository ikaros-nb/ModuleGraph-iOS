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

    @Test func resolvesAProductInItsOwnPackage() throws {
        // Both packages export a product called Shared; Feature asks for the one of Kit.
        let kit = try manifest("""
        { "name": "Kit", "dependencies": [], "products": [ { "name": "Shared", "targets": ["KitShared"] } ],
          "targets": [ { "name": "KitShared", "type": "regular", "dependencies": [] } ] }
        """)
        let other = try manifest("""
        { "name": "Other", "dependencies": [], "products": [ { "name": "Shared", "targets": ["OtherShared"] } ],
          "targets": [ { "name": "OtherShared", "type": "regular", "dependencies": [] },
                       { "name": "Feature", "type": "regular", "dependencies": [ { "product": ["Shared", "Kit", null, null] } ] } ] }
        """)
        let graph = GraphBuilder(root: root, includeTests: false, scanImports: false).build(
            packages: [
                DumpedPackage(directory: root.appendingPathComponent("Kit"), manifest: kit),
                DumpedPackage(directory: root.appendingPathComponent("Other"), manifest: other),
            ],
            projects: [], warnings: [], now: now
        )
        #expect(graph.edges == [Edge(from: "Feature", to: "KitShared", kind: .declared)])
    }

    @Test func scansImports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ path: String, _ text: String) throws {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("Packages/Kit/Sources/Kit/Kit.swift", "import Foundation\nimport Collections\n")
        try write("App/App.swift", "import Kit\nimport Kit\nimport SwiftUI\nimport Lottie\nimport Mystery\n")
        try write("App/Views/Home.swift", "import Kit\n")
        let kit = try manifest("""
        { "name": "Kit", "dependencies": [ { "sourceControl": [ { "identity": "swift-collections" } ] } ], "products": [],
          "targets": [ { "name": "Kit", "type": "regular", "dependencies": [ { "product": ["Collections", "swift-collections", null, null] } ] } ] }
        """)
        let app = XcodeProject(name: "App", directory: dir, targets: [
            XcodeTarget(name: "App", kind: .app, packageProducts: ["Kit", "Lottie"], sourcePaths: ["App"]),
            XcodeTarget(name: "Widget", kind: .app, packageProducts: [], sourcePaths: []),
        ])
        let graph = GraphBuilder(root: dir, includeTests: false, scanImports: true).build(
            packages: [DumpedPackage(directory: dir.appendingPathComponent("Packages/Kit"), manifest: kit)],
            projects: [app], warnings: [], now: now
        )
        #expect(graph.nodes.first { $0.id == "App" }?.sourceFiles == 2)
        #expect(graph.nodes.first { $0.id == "SwiftUI" }?.kind == .system)
        #expect(graph.nodes.first { $0.id == "Lottie" }?.kind == .external)
        #expect(graph.edges.filter { $0.kind == .import } == [
            Edge(from: "App", to: "Kit", kind: .import, count: 3),
            Edge(from: "App", to: "Lottie", kind: .import, count: 1),
            Edge(from: "App", to: "Mystery", kind: .import, count: 1),
            Edge(from: "App", to: "SwiftUI", kind: .import, count: 1),
            Edge(from: "Kit", to: "Collections", kind: .import, count: 1),
            Edge(from: "Kit", to: "Foundation", kind: .import, count: 1),
        ])
        // Lottie is linked by the Xcode target and Collections comes from a remote package: only Mystery is unknown.
        #expect(graph.warnings == [
            Warning(code: "no-sources", path: "App.xcodeproj", message: "no Swift source folder found for Xcode target Widget; its imports are not scanned"),
            Warning(code: "unresolved-import", path: "App", message: "App imports Mystery, which is not a known target"),
        ])
    }

    @Test func redactsAbsolutePathsInMessages() {
        let builder = GraphBuilder(root: URL(fileURLWithPath: "/Users/someone/MyApp"), includeTests: false, scanImports: false)
        let message = "/Users/someone/MyApp/Broken/Package.swift: error, see /Users/someone/Library/Logs and /Users/someone/MyApp"
        #expect(builder.redact(message, home: "/Users/someone") == "Broken/Package.swift: error, see ~/Library/Logs and .")
    }

    @Test func resolvesByNameToATargetOfTheSamePackageFirst() throws {
        // Kit exports a product called Shared made of KitShared; Other has a target called Shared.
        let kit = try manifest("""
        { "name": "Kit", "dependencies": [], "products": [ { "name": "Shared", "targets": ["KitShared"] } ],
          "targets": [ { "name": "KitShared", "type": "regular", "dependencies": [] } ] }
        """)
        let other = try manifest("""
        { "name": "Other", "dependencies": [], "products": [],
          "targets": [ { "name": "Shared", "type": "regular", "dependencies": [] },
                       { "name": "Feature", "type": "regular", "dependencies": [ { "byName": ["Shared", null] } ] } ] }
        """)
        let graph = GraphBuilder(root: root, includeTests: false, scanImports: false).build(
            packages: [
                DumpedPackage(directory: root.appendingPathComponent("Kit"), manifest: kit),
                DumpedPackage(directory: root.appendingPathComponent("Other"), manifest: other),
            ],
            projects: [], warnings: [], now: now
        )
        #expect(graph.edges == [Edge(from: "Feature", to: "Shared", kind: .declared)])
    }
}
