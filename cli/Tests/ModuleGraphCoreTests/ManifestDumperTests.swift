import Foundation
import Testing
@testable import ModuleGraphCore

@Suite struct ManifestDumperTests {
    @Test func drainsBothPipesOfAVerboseProcess() async throws {
        // Far more than a pipe buffer on each stream: reading one pipe after the other would hang.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "head -c 1000000 /dev/zero >&2; head -c 1000000 /dev/zero; exit 3"]
        let output = try await ManifestDumper.run(process)
        #expect(output.status == 3)
        #expect(output.stdout.count == 1_000_000)
        #expect(output.stderr.count == 1_000_000)
    }

    @Test func keepsOnlyTheErrorLinesOfAFailedDump() {
        let stderr = """
        error: 'broken': Invalid manifest (compiled with: ["/Users/someone/swiftc", "-sdk", "/Applications/Xcode.app/MacOSX.sdk"])
        /Users/someone/MyApp/Broken/Package.swift:3:63: error: cannot find 'oops' in scope
        3 | let package = Package(name: "Broken", targets: [.target(name: oops)])
          |                                                               `- error: cannot find 'oops' in scope
        """
        #expect(ManifestDumper.errorSummary(stderr) == """
        error: 'broken': Invalid manifest
        /Users/someone/MyApp/Broken/Package.swift:3:63: error: cannot find 'oops' in scope
        """)
    }
}
