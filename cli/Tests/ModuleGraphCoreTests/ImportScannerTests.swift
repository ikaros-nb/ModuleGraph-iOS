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
}
