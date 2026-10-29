import Foundation

public struct XcodeTarget: Sendable, Equatable {
    public var name: String
    public var kind: Node.Kind
    /// Products of Swift packages linked by this target.
    public var packageProducts: [String]
    /// Source folders, relative to the project directory.
    public var sourcePaths: [String]
}

public struct XcodeProject: Sendable {
    public var name: String
    public var directory: URL
    public var targets: [XcodeTarget]
}

public enum XcodeProjectReader {
    public struct Failure: Error { public var message: String }

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
        throw Failure(message: "no project.xcproj or project.pbxproj in \(projectURL.path)")
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
        var paths: [String: String] = [:]
        for (id, object) in objects where (object["isa"] as? String) == "PBXFileSystemSynchronizedRootGroup" || (object["isa"] as? String) == "PBXGroup" {
            if let path = object["path"] as? String { paths[id] = path }
        }
        return objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" }.compactMap { target in
            guard let name = target["name"] as? String else { return nil }
            let productType = target["productType"] as? String ?? ""
            let productIDs = target["packageProductDependencies"] as? [String] ?? []
            let products = productIDs.compactMap { objects[$0]?["productName"] as? String }
            let groupIDs = target["fileSystemSynchronizedGroups"] as? [String] ?? []
            let sources = groupIDs.compactMap { paths[$0] }
            return XcodeTarget(name: name, kind: kind(forProductType: productType), packageProducts: products.sorted(), sourcePaths: sources.sorted())
        }.sorted { $0.name < $1.name }
    }

    static func kind(forProductType type: String) -> Node.Kind {
        if type.contains("unit-test") || type.contains("ui-testing") || type.contains("test") { return .test }
        if type.contains("application") || type.contains("app-extension") || type.isEmpty { return .app }
        if type.contains("framework") || type.contains("library") { return .library }
        if type.contains("tool") { return .executable }
        return .app
    }
}
