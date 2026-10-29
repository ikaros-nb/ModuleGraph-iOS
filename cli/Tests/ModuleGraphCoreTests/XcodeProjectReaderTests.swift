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

    @Test func readsClassicGroupsFromTheSourcesBuildPhase() throws {
        let text = """
        {
          objects = {
            M = { isa = PBXGroup; children = ( G1, G2 ); sourceTree = "<group>"; };
            G1 = { isa = PBXGroup; name = Extensions; children = ( G3 ); sourceTree = "<group>"; };
            G3 = { isa = PBXGroup; path = Widget; children = ( F1, G4 ); sourceTree = "<group>"; };
            G4 = { isa = PBXGroup; path = Views; children = ( F2 ); sourceTree = "<group>"; };
            G2 = { isa = PBXFileSystemSynchronizedRootGroup; path = Shared; sourceTree = "<group>"; };
            F1 = { isa = PBXFileReference; path = Widget.swift; sourceTree = "<group>"; };
            F2 = { isa = PBXFileReference; path = Row.swift; sourceTree = "<group>"; };
            F3 = { isa = PBXFileReference; path = Info.plist; sourceTree = SOURCE_ROOT; };
            B1 = { isa = PBXBuildFile; fileRef = F1; };
            B2 = { isa = PBXBuildFile; fileRef = F2; };
            B3 = { isa = PBXBuildFile; fileRef = F3; };
            S1 = { isa = PBXSourcesBuildPhase; files = ( B1, B2, B3 ); };
            T1 = { isa = PBXNativeTarget; name = Widget; productType = "com.apple.product-type.app-extension";
                   buildPhases = ( S1 ); fileSystemSynchronizedGroups = ( G2 ); };
          };
        }
        """
        let targets = try XcodeProjectReader.parsePbxproj(Data(text.utf8))
        #expect(targets == [XcodeTarget(
            name: "Widget", kind: .app, packageProducts: [],
            sourcePaths: ["Shared"], sourceFiles: ["Widget/Views/Row.swift", "Widget/Widget.swift"]
        )])
    }
}
