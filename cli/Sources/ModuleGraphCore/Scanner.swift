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
        let location = ProjectLocator.locate(root: root)
        let (packages, dumpWarnings) = await ManifestDumper.dumpAll(directories: location.packageDirectories)
        var warnings = dumpWarnings
        var projects: [XcodeProject] = []
        for projectURL in location.xcodeProjects {
            do {
                projects.append(try XcodeProjectReader.read(projectURL: projectURL))
            } catch {
                warnings.append(Warning(code: "xcodeproj-read-failed", path: projectURL.path, message: "\(error)"))
            }
        }
        let builder = GraphBuilder(root: root, includeTests: options.includeTests, scanImports: options.scanImports)
        return builder.build(packages: packages, projects: projects, warnings: warnings, now: now)
    }
}
