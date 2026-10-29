import Foundation
import Testing
@testable import ModuleGraphCore

@Suite struct ManifestTests {
    @Test func decodesRealDump() throws {
        let url = try #require(Bundle.module.url(forResource: "domain-dump", withExtension: "json", subdirectory: "Fixtures"))
        let manifest = try PackageManifest.decode(try Data(contentsOf: url))
        #expect(manifest.name == "Domain")
        #expect(manifest.products.map(\.name) == ["Domain", "DomainMocks"])
        let domain = try #require(manifest.targets.first { $0.name == "Domain" })
        #expect(domain.type == "regular")
        #expect(domain.dependencies == [
            .product(name: "Toolkit", package: "Toolkit"),
            .product(name: "Observability", package: "Observability"),
            .product(name: "Purchases", package: "Purchases"),
        ])
        let mocks = try #require(manifest.targets.first { $0.name == "DomainMocks" })
        #expect(mocks.dependencies.first == .byName("Domain"))
        #expect(manifest.dependencies.compactMap(\.fileSystem).flatMap { $0 }.map(\.identity).contains("toolkit"))
    }
}
