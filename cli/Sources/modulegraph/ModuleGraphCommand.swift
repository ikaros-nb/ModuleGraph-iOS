import ArgumentParser
import Foundation
import ModuleGraphCore

@main
struct ModuleGraphCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "modulegraph",
        abstract: "Extract the module graph of an iOS project as JSON.",
        subcommands: [Scan.self],
        defaultSubcommand: Scan.self
    )
}

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Scan a project and write its module graph.")

    @Argument(help: "Root directory of the project.")
    var root: String = "."

    @Option(name: .shortAndLong, help: "Output file. Defaults to stdout.")
    var output: String?

    @Flag(name: .customLong("no-imports"), help: "Skip scanning the `import` statements of the sources.")
    var noImports = false

    @Flag(help: "Include the test targets.")
    var includeTests = false

    @Flag(help: "Pretty-print the JSON.")
    var pretty = false

    func run() async throws {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError("\(root) is not a directory")
        }
        let graph = await ModuleGraphCore.Scanner.scan(root: rootURL, options: .init(includeTests: includeTests, scanImports: !noImports))
        let data = try GraphEncoder.encode(graph, pretty: pretty || output == nil)
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
            FileHandle.standardError.write(Data("Wrote \(graph.nodes.count) nodes and \(graph.edges.count) edges to \(output)\n".utf8))
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        for warning in graph.warnings {
            FileHandle.standardError.write(Data("warning[\(warning.code)] \(warning.path ?? ""): \(warning.message)\n".utf8))
        }
    }
}
