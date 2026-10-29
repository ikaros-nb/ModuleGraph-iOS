import Foundation

public struct XcodeTarget: Sendable, Equatable {
    public var name: String
    public var kind: Node.Kind
    /// Products of Swift packages linked by this target.
    public var packageProducts: [String]
    /// Source folders (Xcode 16 synchronized folders), relative to the project directory.
    public var sourcePaths: [String]
    /// Swift files of the Sources build phase outside those folders (classic groups), relative to the project directory.
    public var sourceFiles: [String] = []
}

public struct XcodeProject: Sendable {
    public var name: String
    public var directory: URL
    public var targets: [XcodeTarget]
}

public enum XcodeProjectReader {
    public struct Failure: Error, CustomStringConvertible {
        public var message: String
        public var description: String { message }
    }

    public static func read(projectURL: URL) throws -> XcodeProject {
        let name = projectURL.deletingPathExtension().lastPathComponent
        let directory = projectURL.deletingLastPathComponent()
        let xcproj = projectURL.appendingPathComponent("project.xcproj")
        let pbxproj = projectURL.appendingPathComponent("project.pbxproj")
        let fm = FileManager.default
        if fm.fileExists(atPath: xcproj.path) {
            let text = try String(contentsOf: xcproj, encoding: .utf8)
            return XcodeProject(name: name, directory: directory, targets: try parseXcproj(text))
        }
        if fm.fileExists(atPath: pbxproj.path) {
            let data = try Data(contentsOf: pbxproj)
            return XcodeProject(name: name, directory: directory, targets: try parsePbxproj(data))
        }
        throw Failure(message: "no project.xcproj or project.pbxproj")
    }

    // MARK: - project.xcproj (JSON with trailing commas)

    static func stripTrailingCommas(_ text: String) -> String {
        text.replacing(/,(\s*[\]}])/) { match in String(match.output.1) }
    }

    static func parseXcproj(_ text: String) throws -> [XcodeTarget] {
        let data = Data(stripTrailingCommas(text).utf8)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "project.xcproj is not a JSON object")
        }
        let files = json["files"] as? [[String: Any]] ?? []
        var sourcePaths: [String: [String]] = [:]
        collectSourcePaths(files, prefix: "", into: &sourcePaths)

        let targets = json["targets"] as? [[String: Any]] ?? []
        return targets.compactMap { target in
            guard let name = target["name"] as? String else { return nil }
            let productType = target["product-type"] as? String ?? target["type"] as? String ?? ""
            let deps = target["dependencies"] as? [[String: Any]] ?? []
            let products = deps.filter { $0["kind"] as? String == "package" }.compactMap { $0["product-name"] as? String }
            return XcodeTarget(name: name, kind: kind(forProductType: productType), packageProducts: products, sourcePaths: sourcePaths[name] ?? [])
        }
    }

    private static func collectSourcePaths(_ files: [[String: Any]], prefix: String, into result: inout [String: [String]]) {
        for file in files {
            guard let path = file["path"] as? String else {
                if let children = file["children"] as? [[String: Any]] { collectSourcePaths(children, prefix: prefix, into: &result) }
                continue
            }
            let full = prefix.isEmpty ? path : prefix + "/" + path
            let kind = file["kind"] as? String
            if kind == "folder", let members = file["target-membership"] as? [String] {
                for member in members { result[member, default: []].append(full) }
            } else if let children = file["children"] as? [[String: Any]] {
                collectSourcePaths(children, prefix: full, into: &result)
            }
        }
    }

    // MARK: - project.pbxproj (OpenStep plist)

    static func parsePbxproj(_ data: Data) throws -> [XcodeTarget] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["objects"] as? [String: [String: Any]] else {
            throw Failure(message: "project.pbxproj is not an OpenStep plist")
        }
        var parents: [String: String] = [:]
        for (id, object) in objects {
            for child in object["children"] as? [String] ?? [] { parents[child] = id }
        }
        // Path of a group or file relative to the project directory, following its enclosing groups.
        // Nil when it lives elsewhere (SDK, build products, absolute path).
        func path(of id: String) -> String? {
            guard let object = objects[id] else { return nil }
            let own = object["path"] as? String ?? ""
            switch object["sourceTree"] as? String ?? "<group>" {
            case "<group>":
                guard let parent = parents[id] else { return own }
                return path(of: parent).map { [$0, own].filter { !$0.isEmpty }.joined(separator: "/") }
            case "SOURCE_ROOT": return own
            default: return nil
            }
        }
        return objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" }.compactMap { target in
            guard let name = target["name"] as? String else { return nil }
            let productType = target["productType"] as? String ?? ""
            let productIDs = target["packageProductDependencies"] as? [String] ?? []
            let products = productIDs.compactMap { objects[$0]?["productName"] as? String }
            // Xcode 16 folders, then the Swift files of the Sources build phase: the files themselves rather than
            // their folders, which may hold other targets, or the whole project when a file sits at its root.
            let folders = outermost(Set((target["fileSystemSynchronizedGroups"] as? [String] ?? []).compactMap(path(of:))))
            var files: Set<String> = []
            for phaseID in target["buildPhases"] as? [String] ?? [] {
                guard let phase = objects[phaseID], phase["isa"] as? String == "PBXSourcesBuildPhase" else { continue }
                for buildFileID in phase["files"] as? [String] ?? [] {
                    guard let fileID = objects[buildFileID]?["fileRef"] as? String, let file = path(of: fileID), file.hasSuffix(".swift"),
                          !folders.contains(where: { file.hasPrefix($0 + "/") }) else { continue }
                    files.insert(file)
                }
            }
            return XcodeTarget(name: name, kind: kind(forProductType: productType), packageProducts: products.sorted(), sourcePaths: folders, sourceFiles: files.sorted())
        }.sorted { $0.name < $1.name }
    }

    /// The folders that aren't inside another one of the set, sorted.
    static func outermost(_ folders: Set<String>) -> [String] {
        folders.filter { folder in
            !folders.contains { other in other != folder && (other.isEmpty || folder.hasPrefix(other + "/")) }
        }.sorted()
    }

    static func kind(forProductType type: String) -> Node.Kind {
        if type.contains("unit-test") || type.contains("ui-testing") || type.contains("test") { return .test }
        if type.contains("application") || type.contains("app-extension") || type.isEmpty { return .app }
        if type.contains("framework") || type.contains("library") { return .library }
        if type.contains("tool") { return .executable }
        return .app
    }
}
