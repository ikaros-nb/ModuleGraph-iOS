import Foundation

/// Assembles the graph from dumped packages and Xcode projects.
public struct GraphBuilder: Sendable {
    public var root: URL
    public var includeTests: Bool
    public var scanImports: Bool

    public init(root: URL, includeTests: Bool, scanImports: Bool) {
        self.root = root.standardizedFileURL
        self.includeTests = includeTests
        self.scanImports = scanImports
    }

    struct TargetInfo {
        var node: Node
        var sourceDirectory: URL?
        var declaredDependencies: [PackageManifest.Target.Dependency]
    }

    public func build(packages: [DumpedPackage], projects: [XcodeProject], warnings initialWarnings: [Warning], now: Date) -> Graph {
        var warnings = initialWarnings
        var targets: [String: TargetInfo] = [:]
        // product name -> target ids, scoped by package name and globally.
        var productTargets: [String: [String]] = [:]
        var externalPackages: Set<String> = []
        var externalProducts: Set<String> = []
        var localPackages = Set(packages.map { $0.manifest.name.lowercased() })
        for package in packages {
            for dependency in package.manifest.dependencies {
                for local in dependency.fileSystem ?? [] { localPackages.insert(local.identity.lowercased()) }
            }
        }

        for package in packages {
            let packageName = package.manifest.name
            let packageDir = package.directory.standardizedFileURL
            let group = groupName(for: packageDir)
            for dependency in package.manifest.dependencies {
                for external in dependency.sourceControl ?? [] { externalPackages.insert(external.identity) }
            }
            for product in package.manifest.products {
                productTargets[product.name, default: []].append(contentsOf: product.targets)
            }
            for target in package.manifest.targets {
                // A product that comes from a package which isn't local is external: its modules
                // may be imported under their own names (RxSwift, FirebaseCore…) without a warning.
                for case .product(let name, let packageName?) in target.dependencies where !localPackages.contains(packageName.lowercased()) {
                    externalProducts.insert(name)
                }
                let kind: Node.Kind = switch target.type {
                case "test": .test
                case "executable": .executable
                case "macro": .macro
                default: .library
                }
                if kind == .test, !includeTests { continue }
                if targets[target.name] != nil {
                    warnings.append(Warning(code: "duplicate-target", path: relative(packageDir), message: "target \(target.name) is defined in several packages; keeping the first"))
                    continue
                }
                let sourceDir = sourceDirectory(for: target, kind: kind, packageDir: packageDir, manifest: package.manifest)
                let node = Node(
                    id: target.name,
                    kind: kind,
                    package: packageName,
                    group: group,
                    path: sourceDir.map(relative)
                )
                targets[target.name] = TargetInfo(node: node, sourceDirectory: sourceDir, declaredDependencies: target.dependencies)
            }
        }

        for project in projects {
            for target in project.targets {
                if target.kind == .test, !includeTests { continue }
                if targets[target.name] != nil {
                    warnings.append(Warning(code: "duplicate-target", path: relative(project.directory), message: "Xcode target \(target.name) collides with a package target; keeping the package one"))
                    continue
                }
                let sourceDir = target.sourcePaths.first.map { project.directory.appendingPathComponent($0) }
                let node = Node(id: target.name, kind: target.kind, package: nil, group: "App", path: sourceDir.map(relative))
                let deps = target.packageProducts.map { PackageManifest.Target.Dependency.product(name: $0, package: nil) }
                targets[target.name] = TargetInfo(node: node, sourceDirectory: sourceDir, declaredDependencies: deps)
            }
        }

        var nodes = Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0.value.node) })
        var edges: Set<Edge> = []

        func resolve(product: String) -> [String] {
            if let ids = productTargets[product] { return ids.filter { targets[$0] != nil } }
            if targets[product] != nil { return [product] }
            return []
        }

        for (id, info) in targets {
            for dependency in info.declaredDependencies {
                let resolved: [String]
                var label: String
                switch dependency {
                case .product(let name, _): resolved = resolve(product: name); label = name
                case .byName(let name): resolved = resolve(product: name); label = name
                case .target(let name): resolved = targets[name] != nil ? [name] : []; label = name
                }
                if resolved.isEmpty {
                    let externalId = externalPackages.contains(label.lowercased()) ? label : label
                    nodes[externalId] = nodes[externalId] ?? Node(id: externalId, kind: .external)
                    edges.insert(Edge(from: id, to: externalId, kind: .declared))
                } else {
                    for target in resolved where target != id { edges.insert(Edge(from: id, to: target, kind: .declared)) }
                }
            }
        }

        if scanImports {
            for (id, info) in targets {
                guard let dir = info.sourceDirectory, FileManager.default.fileExists(atPath: dir.path) else {
                    if info.sourceDirectory != nil {
                        warnings.append(Warning(code: "missing-sources", path: info.node.path, message: "source directory of \(id) not found"))
                    }
                    continue
                }
                let scan = ImportScanner.scan(directory: dir)
                nodes[id]?.sourceFiles = scan.sourceFiles
                for (module, count) in scan.imports {
                    if module == id { continue }
                    if targets[module] != nil {
                        edges.insert(Edge(from: id, to: module, kind: .import, count: count))
                    } else if ImportScanner.systemModules.contains(module) {
                        nodes[module] = nodes[module] ?? Node(id: module, kind: .system)
                        edges.insert(Edge(from: id, to: module, kind: .import, count: count))
                    } else if let ids = productTargets[module], !ids.isEmpty {
                        for target in ids where targets[target] != nil {
                            edges.insert(Edge(from: id, to: target, kind: .import, count: count))
                        }
                    } else {
                        nodes[module] = nodes[module] ?? Node(id: module, kind: .external)
                        edges.insert(Edge(from: id, to: module, kind: .import, count: count))
                        if !externalPackages.contains(module.lowercased()), !externalProducts.contains(module) {
                            warnings.append(Warning(code: "unresolved-import", path: info.node.path, message: "\(id) imports \(module), which is not a known target"))
                        }
                    }
                }
            }
        }

        let sortedNodes = nodes.values.sorted { $0.id < $1.id }
        let sortedEdges = edges.sorted { ($0.from, $0.to, $0.kind.rawValue) < ($1.from, $1.to, $1.kind.rawValue) }
        let sortedWarnings = warnings.sorted { ($0.code, $0.path ?? "", $0.message) < ($1.code, $1.path ?? "", $1.message) }
        return Graph(project: root.lastPathComponent, generatedAt: now, nodes: sortedNodes, edges: sortedEdges, warnings: sortedWarnings)
    }

    func relative(_ url: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
    }

    func groupName(for packageDir: URL) -> String? {
        let components = relative(packageDir).split(separator: "/").map(String.init)
        guard components.count >= 2 else { return components.first }
        return components.dropLast().joined(separator: "/")
    }

    func sourceDirectory(for target: PackageManifest.Target, kind: Node.Kind, packageDir: URL, manifest: PackageManifest) -> URL? {
        if let path = target.path { return packageDir.appendingPathComponent(path) }
        let folder = kind == .test ? "Tests" : "Sources"
        let conventional = packageDir.appendingPathComponent(folder).appendingPathComponent(target.name)
        if FileManager.default.fileExists(atPath: conventional.path) { return conventional }
        // SwiftPM lets a package with a single target of that kind keep its files directly in Sources/ or Tests/.
        let siblings = manifest.targets.filter { ($0.type == "test") == (kind == .test) }
        if siblings.count == 1 { return packageDir.appendingPathComponent(folder) }
        return conventional
    }
}
