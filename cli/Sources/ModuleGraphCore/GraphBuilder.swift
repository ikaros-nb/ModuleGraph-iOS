import Foundation

/// Assembles the graph from dumped packages and Xcode projects, in three phases: collect the targets,
/// link their declared dependencies, then scan their `import` statements.
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
        var sourceDirectories: [URL]
        /// Single files to scan besides the directories, from the Sources build phase of an Xcode target.
        var files: [URL] = []
        var declaredDependencies: [PackageManifest.Target.Dependency]
    }

    /// Every target of the project, and what is needed to resolve a dependency or an import to one of them.
    struct Catalog {
        var targets: [String: TargetInfo] = [:]
        /// Product name -> target ids, per local package (by lowercased name and directory) and across all of them.
        var productsByPackage: [String: [String: [String]]] = [:]
        var products: [String: [String]] = [:]
        /// Identities of the remote packages, and the products taken from them: these may be imported without a warning.
        var externalPackages: Set<String> = []
        var externalProducts: Set<String> = []
        var warnings: [Warning] = []

        func resolve(product: String, package: String? = nil) -> [String] {
            if let package = package?.lowercased() {
                if externalPackages.contains(package) { return [] }
                if let ids = productsByPackage[package]?[product] { return ids.filter { targets[$0] != nil } }
            }
            if let ids = products[product] { return ids.filter { targets[$0] != nil } }
            return targets[product] != nil ? [product] : []
        }
    }

    public func build(packages: [DumpedPackage], projects: [XcodeProject], warnings: [Warning], now: Date) -> Graph {
        let catalog = collectTargets(packages: packages, projects: projects)
        var nodes = Dictionary(uniqueKeysWithValues: catalog.targets.map { ($0.key, $0.value.node) })
        var edges: Set<Edge> = []
        var warnings = warnings + catalog.warnings
        addDeclaredEdges(catalog, nodes: &nodes, edges: &edges)
        if scanImports { addImportEdges(catalog, nodes: &nodes, edges: &edges, warnings: &warnings) }

        let sortedNodes = nodes.values.sorted { $0.id < $1.id }
        let sortedEdges = edges.sorted { ($0.from, $0.to, $0.kind.rawValue) < ($1.from, $1.to, $1.kind.rawValue) }
        let sortedWarnings = warnings.sorted { ($0.code, $0.path ?? "", $0.message) < ($1.code, $1.path ?? "", $1.message) }
        return Graph(project: root.lastPathComponent, generatedAt: now, nodes: sortedNodes, edges: sortedEdges, warnings: sortedWarnings)
    }

    // MARK: - Phase 1: targets

    func collectTargets(packages: [DumpedPackage], projects: [XcodeProject]) -> Catalog {
        var catalog = Catalog()
        var localPackages = Set(packages.map { $0.manifest.name.lowercased() })
        for package in packages {
            localPackages.insert(package.directory.lastPathComponent.lowercased())
            for dependency in package.manifest.dependencies {
                for local in dependency.fileSystem ?? [] { localPackages.insert(local.identity.lowercased()) }
                for external in dependency.sourceControl ?? [] { catalog.externalPackages.insert(external.identity.lowercased()) }
            }
        }

        for package in packages {
            let packageDir = package.directory.standardizedFileURL
            let group = groupName(for: packageDir)
            for product in package.manifest.products {
                catalog.products[product.name, default: []].append(contentsOf: product.targets)
                for key in Set([package.manifest.name.lowercased(), packageDir.lastPathComponent.lowercased()]) {
                    catalog.productsByPackage[key, default: [:]][product.name, default: []].append(contentsOf: product.targets)
                }
            }
            for target in package.manifest.targets {
                // A product that comes from a package which isn't local is external: its modules
                // may be imported under their own names (RxSwift, FirebaseCore…) without a warning.
                for case .product(let name, let packageName?) in target.dependencies where !localPackages.contains(packageName.lowercased()) {
                    catalog.externalProducts.insert(name)
                }
                let kind: Node.Kind = switch target.type {
                case "test": .test
                case "executable": .executable
                case "macro": .macro
                default: .library
                }
                if kind == .test, !includeTests { continue }
                if catalog.targets[target.name] != nil {
                    catalog.warnings.append(Warning(code: "duplicate-target", path: relative(packageDir), message: "target \(target.name) is defined in several packages; keeping the first"))
                    continue
                }
                let sourceDir = sourceDirectory(for: target, kind: kind, packageDir: packageDir, manifest: package.manifest)
                let node = Node(id: target.name, kind: kind, package: package.manifest.name, group: group, path: relative(sourceDir))
                catalog.targets[target.name] = TargetInfo(node: node, sourceDirectories: [sourceDir], declaredDependencies: target.dependencies)
            }
        }

        for project in projects {
            let projectPath = relative(project.directory.appendingPathComponent(project.name + ".xcodeproj"))
            for target in project.targets {
                if target.kind == .test, !includeTests { continue }
                if catalog.targets[target.name] != nil {
                    catalog.warnings.append(Warning(code: "duplicate-target", path: projectPath, message: "Xcode target \(target.name) collides with a package target; keeping the package one"))
                    continue
                }
                let sourceDirs = target.sourcePaths.map { project.directory.appendingPathComponent($0) }
                let files = target.sourceFiles.map { project.directory.appendingPathComponent($0) }
                if scanImports, sourceDirs.isEmpty, files.isEmpty {
                    catalog.warnings.append(Warning(code: "no-sources", path: projectPath, message: "no Swift source folder found for Xcode target \(target.name); its imports are not scanned"))
                }
                // Shown as the target's folder: its first source folder, or the one that holds its files.
                let fileFolders = XcodeProjectReader.outermost(Set(target.sourceFiles.map { ($0 as NSString).deletingLastPathComponent }))
                let folder = target.sourcePaths.first ?? fileFolders.first
                let node = Node(id: target.name, kind: target.kind, package: nil, group: "App", path: folder.map { relative(project.directory.appendingPathComponent($0)) })
                let deps = target.packageProducts.map { PackageManifest.Target.Dependency.product(name: $0, package: nil) }
                    + target.targetDependencies.map { PackageManifest.Target.Dependency.target($0) }
                catalog.targets[target.name] = TargetInfo(node: node, sourceDirectories: sourceDirs, files: files, declaredDependencies: deps)
            }
        }

        // A product linked by an Xcode target that no local package provides comes from a remote package.
        for project in projects {
            for target in project.targets {
                for product in target.packageProducts where catalog.resolve(product: product).isEmpty {
                    catalog.externalProducts.insert(product)
                }
            }
        }
        return catalog
    }

    // MARK: - Phase 2: declared dependencies

    func addDeclaredEdges(_ catalog: Catalog, nodes: inout [String: Node], edges: inout Set<Edge>) {
        for (id, info) in catalog.targets {
            for dependency in info.declaredDependencies {
                let name: String
                let resolved: [String]
                switch dependency {
                case .product(let product, let package): name = product; resolved = catalog.resolve(product: product, package: package)
                case .byName(let target): name = target; resolved = catalog.resolve(product: target)
                case .target(let target): name = target; resolved = catalog.targets[target] != nil ? [target] : []
                }
                if resolved.isEmpty {
                    nodes[name] = nodes[name] ?? Node(id: name, kind: .external)
                    edges.insert(Edge(from: id, to: name, kind: .declared))
                } else {
                    for target in resolved where target != id { edges.insert(Edge(from: id, to: target, kind: .declared)) }
                }
            }
        }
    }

    // MARK: - Phase 3: imports

    func addImportEdges(_ catalog: Catalog, nodes: inout [String: Node], edges: inout Set<Edge>, warnings: inout [Warning]) {
        for (id, info) in catalog.targets {
            var sourceFiles: Int?
            var imports: [String: Int] = [:]
            for dir in info.sourceDirectories {
                guard FileManager.default.fileExists(atPath: dir.path) else {
                    warnings.append(Warning(code: "missing-sources", path: relative(dir), message: "source directory of \(id) not found"))
                    continue
                }
                let scan = ImportScanner.scan(directory: dir)
                sourceFiles = (sourceFiles ?? 0) + scan.sourceFiles
                imports.merge(scan.imports, uniquingKeysWith: +)
            }
            if !info.files.isEmpty {
                let scan = ImportScanner.scan(files: info.files)
                sourceFiles = (sourceFiles ?? 0) + scan.sourceFiles
                imports.merge(scan.imports, uniquingKeysWith: +)
            }
            nodes[id]?.sourceFiles = sourceFiles
            for (module, count) in imports where module != id {
                if catalog.targets[module] != nil {
                    edges.insert(Edge(from: id, to: module, kind: .import, count: count))
                } else if ImportScanner.systemModules.contains(module) {
                    nodes[module] = nodes[module] ?? Node(id: module, kind: .system)
                    edges.insert(Edge(from: id, to: module, kind: .import, count: count))
                } else if let ids = catalog.products[module], !ids.isEmpty {
                    for target in ids where catalog.targets[target] != nil {
                        edges.insert(Edge(from: id, to: target, kind: .import, count: count))
                    }
                } else {
                    nodes[module] = nodes[module] ?? Node(id: module, kind: .external)
                    edges.insert(Edge(from: id, to: module, kind: .import, count: count))
                    if !catalog.externalPackages.contains(module.lowercased()), !catalog.externalProducts.contains(module) {
                        warnings.append(Warning(code: "unresolved-import", path: info.node.path, message: "\(id) imports \(module), which is not a known target"))
                    }
                }
            }
        }
    }

    // MARK: - Paths

    /// `url` relative to the root, or its last component when it lies outside: the JSON never holds an absolute path.
    func relative(_ url: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.path
        if path + "/" == rootPath { return "" }
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : url.lastPathComponent
    }

    /// `message` with the root's absolute path made relative and the home folder replaced by `~`.
    /// The root is matched both as given and as `realpath` spells it, the way tools report it (`/tmp` → `/private/tmp`):
    /// Foundation's own symlink resolution drops that `/private`.
    func redact(_ message: String, home: String = NSHomeDirectory()) -> String {
        var message = message
        let realPath = realpath(root.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        // The longest first: `/tmp/x` is also the end of `/private/tmp/x`.
        for rootPath in Set([root.path, realPath ?? root.path]).sorted(by: { $0.count > $1.count }) where rootPath != "/" {
            message = message.replacingOccurrences(of: rootPath + "/", with: "").replacingOccurrences(of: rootPath, with: ".")
        }
        if !home.isEmpty, home != "/" { message = message.replacingOccurrences(of: home, with: "~") }
        return message
    }

    func groupName(for packageDir: URL) -> String? {
        let components = relative(packageDir).split(separator: "/").map(String.init)
        guard components.count >= 2 else { return components.first }
        return components.dropLast().joined(separator: "/")
    }

    func sourceDirectory(for target: PackageManifest.Target, kind: Node.Kind, packageDir: URL, manifest: PackageManifest) -> URL {
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
