import Foundation

public struct ProjectLocation: Sendable {
    public var packageDirectories: [URL]
    public var xcodeProjects: [URL]
}

public enum ProjectLocator {
    static let ignoredDirectories: Set<String> = [
        ".build", ".swiftpm", "DerivedData", "node_modules", ".git", "Pods", "Carthage", "build", "dist",
    ]

    public static func locate(root: URL) -> ProjectLocation {
        var ignored = ignoredDirectories
        for line in gitignoreEntries(root: root) { ignored.insert(line) }

        var packages: [URL] = []
        var projects: [URL] = []
        var queue = [root]
        let fm = FileManager.default
        while let dir = queue.popLast() {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if name == "Package.swift" {
                    packages.append(dir)
                } else if isDir, name.hasSuffix(".xcodeproj") {
                    projects.append(entry)
                } else if isDir, !ignored.contains(name), !name.hasSuffix(".xcassets"), !name.hasSuffix(".xcworkspace") {
                    queue.append(entry)
                }
            }
        }
        return ProjectLocation(
            packageDirectories: packages.sorted { $0.path < $1.path },
            xcodeProjects: projects.sorted { $0.path < $1.path }
        )
    }

    static func gitignoreEntries(root: URL) -> [String] {
        guard let text = try? String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("!") else { return nil }
            if line.hasPrefix("/") { line.removeFirst() }
            if line.hasSuffix("/") { line.removeLast() }
            guard !line.contains("/"), !line.contains("*") else { return nil }
            return line
        }
    }
}
