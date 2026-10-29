import Foundation

public enum Scanner {
    public struct Options: Sendable {
        public var includeTests: Bool
        public var scanImports: Bool
        public init(includeTests: Bool = false, scanImports: Bool = true) {
            self.includeTests = includeTests
            self.scanImports = scanImports
        }
    }

    public static func scan(root: URL, options: Options, now: Date = Date()) async -> Graph {
        let builder = GraphBuilder(root: root, includeTests: options.includeTests, scanImports: options.scanImports)
        let location = ProjectLocator.locate(root: root)
        let (packages, failures) = await ManifestDumper.dumpAll(directories: location.packageDirectories)
        // Warning paths are relative to the root, so that the JSON doesn't reveal where the project lives.
        var warnings = failures.map { Warning(code: "manifest-dump-failed", path: builder.relative($0.directory), message: $0.message) }
        var projects: [XcodeProject] = []
        for projectURL in location.xcodeProjects {
            do {
                projects.append(try XcodeProjectReader.read(projectURL: projectURL))
            } catch {
                warnings.append(Warning(code: "xcodeproj-read-failed", path: builder.relative(projectURL), message: "\(error)"))
            }
        }
        return builder.build(packages: packages, projects: projects, warnings: warnings, now: now)
    }
}
