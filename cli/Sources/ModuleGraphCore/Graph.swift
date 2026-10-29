import Foundation

public struct Graph: Codable, Sendable, Equatable {
    public var version: Int = 1
    public var project: String
    public var generatedAt: Date
    public var nodes: [Node]
    public var edges: [Edge]
    public var warnings: [Warning]

    public init(project: String, generatedAt: Date, nodes: [Node], edges: [Edge], warnings: [Warning]) {
        self.project = project
        self.generatedAt = generatedAt
        self.nodes = nodes
        self.edges = edges
        self.warnings = warnings
    }
}

public struct Node: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case app, library, test, executable, macro, system, external
    }

    public var id: String
    public var kind: Kind
    public var package: String?
    public var group: String?
    public var path: String?
    public var sourceFiles: Int?

    public init(id: String, kind: Kind, package: String? = nil, group: String? = nil, path: String? = nil, sourceFiles: Int? = nil) {
        self.id = id
        self.kind = kind
        self.package = package
        self.group = group
        self.path = path
        self.sourceFiles = sourceFiles
    }
}

public struct Edge: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case declared, `import`
    }

    public var from: String
    public var to: String
    public var kind: Kind
    public var count: Int?

    public init(from: String, to: String, kind: Kind, count: Int? = nil) {
        self.from = from
        self.to = to
        self.kind = kind
        self.count = count
    }
}

public struct Warning: Codable, Sendable, Equatable {
    public var code: String
    public var path: String?
    public var message: String

    public init(code: String, path: String? = nil, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

public enum GraphEncoder {
    public static func encode(_ graph: Graph, pretty: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(graph)
    }
}
