import Foundation
import Testing
@testable import ModuleGraphCore

@Suite struct XcodeProjectReaderTests {
    @Test func stripsTrailingCommas() {
        let text = "{ \"a\": [1, 2,], \"b\": { \"c\": 3, },\n}"
        #expect(XcodeProjectReader.stripTrailingCommas(text) == "{ \"a\": [1, 2], \"b\": { \"c\": 3 }\n}")
    }

    @Test func readsXcprojTargets() throws {
        let text = """
        {
          "files": [
            { "kind": "folder", "path": "App", "target-membership": ["App",], },
          ],
          "targets": [
            {
              "name": "App",
              "product-type": "com.apple.product-type.application",
              "dependencies": [
                { "kind": "package", "package": "Domain", "product-name": "Domain" },
                { "kind": "package", "package": "Domain", "product-name": "DomainMocks" },
              ],
            },
          ],
        }
        """
        let targets = try XcodeProjectReader.parseXcproj(text)
        #expect(targets == [XcodeTarget(name: "App", kind: .app, packageProducts: ["Domain", "DomainMocks"], sourcePaths: ["App"])])
    }

    @Test func readsPbxprojTargets() throws {
        let text = """
        // !$*UTF8*$!
        {
          objects = {
            T1 = { isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application";
                   packageProductDependencies = ( P1 ); fileSystemSynchronizedGroups = ( G1 ); };
            T2 = { isa = PBXNativeTarget; name = AppTests; productType = "com.apple.product-type.bundle.unit-test"; };
            P1 = { isa = XCSwiftPackageProductDependency; productName = Domain; };
            G1 = { isa = PBXFileSystemSynchronizedRootGroup; path = App; };
          };
        }
        """
        let targets = try XcodeProjectReader.parsePbxproj(Data(text.utf8))
        #expect(targets == [
            XcodeTarget(name: "App", kind: .app, packageProducts: ["Domain"], sourcePaths: ["App"]),
            XcodeTarget(name: "AppTests", kind: .test, packageProducts: [], sourcePaths: []),
        ])
    }
}
