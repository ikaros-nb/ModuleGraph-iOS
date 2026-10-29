import Foundation
import Testing
@testable import ModuleGraphCore

@Suite struct ImportScannerTests {
    @Test func recognisesEveryImportForm() {
        let source = """
        import Foundation
        public import SwiftUI
        @testable import Persistence
        internal import struct Foundation.Date
        @preconcurrency import Combine
          import os
        let x = 1
        """
        #expect(ImportScanner.imports(in: source) == [
            "Foundation": 2, "SwiftUI": 1, "Persistence": 1, "Combine": 1, "os": 1,
        ])
    }

    @Test func ignoresTextThatIsNotAStatement() {
        let source = """
        // we used to import Legacy here
        let text = "import Fake"
        importantValue = 3
        """
        let imports = ImportScanner.imports(in: source)
        #expect(imports["Fake"] == nil)
        #expect(imports["importantValue"] == nil)
        // `import` must start the line, so a line comment never matches. Inside a /* */ block it would.
        #expect(imports["Legacy"] == nil)
    }

    @Test func scansOnlyTheFolderOwnSources() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ path: String, _ text: String) throws {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("AppDelegate.swift", "import UIKit\n")
        try write("Package.swift", "import PackageDescription\n")
        try write("Packages/Kit/Package.swift", "import PackageDescription\n")
        try write("Packages/Kit/Sources/Kit/Kit.swift", "import Alamofire\n")
        try write(".build/checkouts/Lib/Lib.swift", "import Hidden\n")
        try write("DerivedData/Generated.swift", "import Generated\n")
        try write("App.xcodeproj/Template.swift", "import Template\n")
        let scan = ImportScanner.scan(directory: dir)
        #expect(scan.sourceFiles == 1)
        #expect(scan.imports == ["UIKit": 1])
    }
}
