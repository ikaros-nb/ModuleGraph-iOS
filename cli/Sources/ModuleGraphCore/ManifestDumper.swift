import Foundation

/// The subset of `swift package dump-package` the graph needs.
public struct PackageManifest: Decodable, Sendable {
    public struct Product: Decodable, Sendable {
        public var name: String
        public var targets: [String]
    }

    public struct Target: Decodable, Sendable {
        public enum Dependency: Decodable, Sendable, Equatable {
            case product(name: String, package: String?)
            case byName(String)
            case target(String)

            private enum CodingKeys: String, CodingKey { case product, byName, target }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let values = try container.decodeIfPresent([String?].self, forKey: .product) {
                    self = .product(name: values.first.flatMap { $0 } ?? "", package: values.dropFirst().first.flatMap { $0 })
                } else if let values = try container.decodeIfPresent([String?].self, forKey: .byName) {
                    self = .byName(values.first.flatMap { $0 } ?? "")
                } else if let values = try container.decodeIfPresent([String?].self, forKey: .target) {
                    self = .target(values.first.flatMap { $0 } ?? "")
                } else {
                    throw DecodingError.dataCorruptedError(forKey: .product, in: container, debugDescription: "Unknown target dependency")
                }
            }
        }

        public var name: String
        public var type: String
        public var path: String?
        public var dependencies: [Dependency]
    }

    public struct PackageDependency: Decodable, Sendable {
        public struct FileSystem: Decodable, Sendable {
            public var identity: String
            public var path: String
        }
        public struct SourceControl: Decodable, Sendable {
            public var identity: String
        }
        public var fileSystem: [FileSystem]?
        public var sourceControl: [SourceControl]?
    }

    public var name: String
    public var products: [Product]
    public var targets: [Target]
    public var dependencies: [PackageDependency]

    public static func decode(_ data: Data) throws -> PackageManifest {
        try JSONDecoder().decode(PackageManifest.self, from: data)
    }
}

public struct DumpedPackage: Sendable {
    public var directory: URL
    public var manifest: PackageManifest
}

public enum ManifestDumper {
    public struct Failure: Error, Sendable {
        public var directory: URL
        public var message: String
    }

    public static func dump(directory: URL) async throws -> PackageManifest {
        let process = Process()
        // `xcrun` reaches the Xcode toolchain directly, so a `.swift-version` file that a toolchain
        // manager such as swiftly can't satisfy doesn't block the dump.
        if FileManager.default.fileExists(atPath: "/usr/bin/xcrun") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        }
        process.arguments = ["swift", "package", "dump-package"]
        process.currentDirectoryURL = directory
        let output = try await run(process)
        guard output.status == 0 else {
            let message = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(directory: directory, message: message.isEmpty ? "exit \(output.status)" : message)
        }
        do {
            return try PackageManifest.decode(output.stdout)
        } catch {
            throw Failure(directory: directory, message: "cannot decode dump-package output: \(error)")
        }
    }

    /// Runs `process` to completion on a Dispatch thread rather than the cooperative pool, draining
    /// stdout and stderr concurrently so that a full pipe can never block the child.
    static func run(_ process: Process) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                } catch {
                    return continuation.resume(throwing: error)
                }
                let errors = DataBox()
                let group = DispatchGroup()
                DispatchQueue.global().async(group: group) { errors.data = stderr.fileHandleForReading.readDataToEndOfFile() }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, output, errors.data))
            }
        }
    }

    /// Written by one reader thread, read after `DispatchGroup.wait()`.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// Dumps every package, at most one per processor at a time.
    public static func dumpAll(directories: [URL]) async -> (packages: [DumpedPackage], failures: [Failure]) {
        await withTaskGroup(of: Result<DumpedPackage, Failure>.self) { group in
            var pending = directories[...]
            func addNext() {
                guard let directory = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return .success(DumpedPackage(directory: directory, manifest: try await dump(directory: directory)))
                    } catch let failure as Failure {
                        return .failure(failure)
                    } catch {
                        return .failure(Failure(directory: directory, message: "\(error)"))
                    }
                }
            }
            for _ in 0..<max(1, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
            var packages: [DumpedPackage] = []
            var failures: [Failure] = []
            for await result in group {
                switch result {
                case .success(let package): packages.append(package)
                case .failure(let failure): failures.append(failure)
                }
                addNext()
            }
            packages.sort { $0.directory.path < $1.directory.path }
            failures.sort { $0.directory.path < $1.directory.path }
            return (packages, failures)
        }
    }
}
